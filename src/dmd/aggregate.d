/**
 * Defines a `Dsymbol` representing an aggregate, which is a `struct`, `union` or `class`.
 *
 * Specification: $(LINK2 https://dlang.org/spec/struct.html, Structs, Unions),
 *                $(LINK2 https://dlang.org/spec/class.html, Class).
 *
 * Copyright:   Copyright (C) 1999-2020 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/aggregate.d, _aggregate.d)
 * Documentation:  https://dlang.org/phobos/dmd_aggregate.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/aggregate.d
 */

module dmd.aggregate;

import core.stdc.stdio;
import core.checkedint;

import dmd.aliasthis;
import dmd.apply;
import dmd.arraytypes;
import dmd.gluelayer : Symbol;
import dmd.declaration;
import dmd.dscope;
import dmd.dstruct;
import dmd.dsymbol;
import dmd.dsymbolsem;
import dmd.dtemplate;
import dmd.errors;
import dmd.expression;
import dmd.func;
import dmd.globals;
import dmd.id;
import dmd.identifier;
import dmd.mtype;
import dmd.tokens;
import dmd.typesem : defaultInit;
import dmd.visitor;

enum Sizeok : int
{
    none,           /// size of aggregate is not yet able to compute
    fwd,            /// size of aggregate is ready to compute
    inProcess,      /// in the midst of computing the size
    done,           /// size of aggregate is set correctly
}

enum Baseok : int
{
    none,             /// base classes not computed yet
    start,            /// in process of resolving base classes
    done,             /// all base classes are resolved
    semanticdone,     /// all base classes semantic done
}

/**
 * The ClassKind enum is used in AggregateDeclaration AST nodes to
 * specify the linkage type of the struct/class/interface or if it
 * is an anonymous class. If the class is anonymous it is also
 * considered to be a D class.
 */
enum ClassKind : int
{
    /// the aggregate is a d(efault) class
    d,
    /// the aggregate is a C++ struct/class/interface
    cpp,
    /// the aggregate is an Objective-C class/interface
    objc,
}

/***********************************************************
 * Abstract aggregate as a common ancestor for Class- and StructDeclaration.
 */
extern (C++) abstract class AggregateDeclaration : ScopeDsymbol
{
    Type type;                  ///
    StorageClass storage_class; ///
    Prot protection;            /// visibility
    uint structsize;            /// size of struct
    uint alignsize;             /// size of struct for alignment purposes
    VarDeclarations fields;     /// VarDeclaration fields
    Sizeok sizeok = Sizeok.none;/// set when structsize contains valid data
    Dsymbol deferred;           /// any deferred semantic2() or semantic3() symbol

    /// specifies whether this is a D, C++, Objective-C or anonymous struct/class/interface
    ClassKind classKind;
    /// Specify whether to mangle the aggregate as a `class` or a `struct`
    /// This information is used by the MSVC mangler
    /// Only valid for class and struct. TODO: Merge with ClassKind ?
    CPPMANGLE cppmangle;

    /**
     * !=null if is nested
     * pointing to the dsymbol that directly enclosing it.
     * 1. The function that enclosing it (nested struct and class)
     * 2. The class that enclosing it (nested class only)
     * 3. If enclosing aggregate is template, its enclosing dsymbol.
     *
     * See AggregateDeclaraton::makeNested for the details.
     */
    Dsymbol enclosing;

    VarDeclaration vthis;   /// 'this' parameter if this aggregate is nested
    VarDeclaration vthis2;  /// 'this' parameter if this aggregate is a template and is nested

    // Special member functions
    FuncDeclarations invs;  /// Array of invariants
    FuncDeclaration inv;    /// Merged invariant calling all members of invs
    NewDeclaration aggNew;  /// allocator

    /// CtorDeclaration or TemplateDeclaration
    Dsymbol ctor;

    /// default constructor - should have no arguments, because
    /// it would be stored in TypeInfo_Class.defaultConstructor
    CtorDeclaration defaultCtor;

    AliasThis aliasthis;    /// forward unresolved lookups to aliasthis
    bool noDefaultCtor;     /// no default construction

    DtorDeclarations dtors;     /// Array of destructors
    DtorDeclaration dtor;       /// aggregate destructor calling dtors and member constructors
    DtorDeclaration primaryDtor;/// non-deleting C++ destructor, same as dtor for D
    DtorDeclaration tidtor;     /// aggregate destructor used in TypeInfo (must have extern(D) ABI)
    FuncDeclaration fieldDtor;  /// aggregate destructor for just the fields

    Expression getRTInfo;   /// pointer to GC info generated by object.RTInfo(this)

    final extern (D) this(const ref Loc loc, Identifier id)
    {
        super(loc, id);
        protection = Prot(Prot.Kind.public_);
    }

    /***************************************
     * Create a new scope from sc.
     * semantic, semantic2 and semantic3 will use this for aggregate members.
     */
    Scope* newScope(Scope* sc)
    {
        auto sc2 = sc.push(this);
        sc2.stc &= STCFlowThruAggregate;
        sc2.parent = this;
        sc2.inunion = isUnionDeclaration();
        sc2.protection = Prot(Prot.Kind.public_);
        sc2.explicitProtection = 0;
        sc2.aligndecl = null;
        sc2.userAttribDecl = null;
        sc2.namespace = null;
        return sc2;
    }

    override final void setScope(Scope* sc)
    {
        // Might need a scope to resolve forward references. The check for
        // semanticRun prevents unnecessary setting of _scope during deferred
        // setScope phases for aggregates which already finished semantic().
        // See https://issues.dlang.org/show_bug.cgi?id=16607
        if (semanticRun < PASS.semanticdone)
            ScopeDsymbol.setScope(sc);
    }

    /***************************************
     * Find all instance fields, then push them into `fields`.
     *
     * Runs semantic() for all instance field variables, but also
     * the field types can remain yet not resolved forward references,
     * except direct recursive definitions.
     * After the process sizeok is set to Sizeok.fwd.
     *
     * Returns:
     *      false if any errors occur.
     */
    final bool determineFields()
    {
        if (_scope)
            dsymbolSemantic(this, null);
        if (sizeok != Sizeok.none)
            return true;

        //printf("determineFields() %s, fields.dim = %d\n", toChars(), fields.dim);
        // determineFields can be called recursively from one of the fields's v.semantic
        fields.setDim(0);

        static int func(Dsymbol s, AggregateDeclaration ad)
        {
            auto v = s.isVarDeclaration();
            if (!v)
                return 0;
            if (v.storage_class & STC.manifest)
                return 0;

            if (v.semanticRun < PASS.semanticdone)
                v.dsymbolSemantic(null);
            // Return in case a recursive determineFields triggered by v.semantic already finished
            if (ad.sizeok != Sizeok.none)
                return 1;

            if (v.aliassym)
                return 0;   // If this variable was really a tuple, skip it.

            if (v.storage_class & (STC.static_ | STC.extern_ | STC.tls | STC.gshared | STC.manifest | STC.ctfe | STC.templateparameter))
                return 0;
            if (!v.isField() || v.semanticRun < PASS.semanticdone)
                return 1;   // unresolvable forward reference

            ad.fields.push(v);

            if (v.storage_class & STC.ref_)
                return 0;
            auto tv = v.type.baseElemOf();
            if (tv.ty != Tstruct)
                return 0;
            if (ad == (cast(TypeStruct)tv).sym)
            {
                const(char)* psz = (v.type.toBasetype().ty == Tsarray) ? "static array of " : "";
                ad.error("cannot have field `%s` with %ssame struct type", v.toChars(), psz);
                ad.type = Type.terror;
                ad.errors = true;
                return 1;
            }
            return 0;
        }

        if (members)
        {
            for (size_t i = 0; i < members.dim; i++)
            {
                auto s = (*members)[i];
                if (s.apply(&func, this))
                {
                    if (sizeok != Sizeok.none)
                    {
                        // recursive determineFields already finished
                        return true;
                    }
                    return false;
                }
            }
        }

        if (sizeok != Sizeok.done)
            sizeok = Sizeok.fwd;

        return true;
    }

    /***************************************
     * Returns:
     *      The total number of fields minus the number of hidden fields.
     */
    final size_t nonHiddenFields()
    {
        return fields.dim - isNested() - (vthis2 !is null);
    }

    /***************************************
     * Collect all instance fields, then determine instance size.
     * Returns:
     *      false if failed to determine the size.
     */
    final bool determineSize(Loc loc)
    {
        //printf("AggregateDeclaration::determineSize() %s, sizeok = %d\n", toChars(), sizeok);

        // The previous instance size finalizing had:
        if (type.ty == Terror)
            return false;   // failed already
        if (sizeok == Sizeok.done)
            return true;    // succeeded

        if (!members)
        {
            error(loc, "unknown size");
            return false;
        }

        if (_scope)
            dsymbolSemantic(this, null);

        // Determine the instance size of base class first.
        if (auto cd = isClassDeclaration())
        {
            cd = cd.baseClass;
            if (cd && !cd.determineSize(loc))
                goto Lfail;
        }

        // Determine instance fields when sizeok == Sizeok.none
        if (!determineFields())
            goto Lfail;
        if (sizeok != Sizeok.done)
            finalizeSize();

        // this aggregate type has:
        if (type.ty == Terror)
            return false;   // marked as invalid during the finalizing.
        if (sizeok == Sizeok.done)
            return true;    // succeeded to calculate instance size.

    Lfail:
        // There's unresolvable forward reference.
        if (type != Type.terror)
            error(loc, "no size because of forward reference");
        // Don't cache errors from speculative semantic, might be resolvable later.
        // https://issues.dlang.org/show_bug.cgi?id=16574
        if (!global.gag)
        {
            type = Type.terror;
            errors = true;
        }
        return false;
    }

    abstract void finalizeSize();

    override final d_uns64 size(const ref Loc loc)
    {
        //printf("+AggregateDeclaration::size() %s, scope = %p, sizeok = %d\n", toChars(), _scope, sizeok);
        bool ok = determineSize(loc);
        //printf("-AggregateDeclaration::size() %s, scope = %p, sizeok = %d\n", toChars(), _scope, sizeok);
        return ok ? structsize : SIZE_INVALID;
    }

    /***************************************
     * Calculate field[i].overlapped and overlapUnsafe, and check that all of explicit
     * field initializers have unique memory space on instance.
     * Returns:
     *      true if any errors happen.
     */
    extern (D) final bool checkOverlappedFields()
    {
        //printf("AggregateDeclaration::checkOverlappedFields() %s\n", toChars());
        assert(sizeok == Sizeok.done);
        size_t nfields = fields.dim;
        if (isNested())
        {
            auto cd = isClassDeclaration();
            if (!cd || !cd.baseClass || !cd.baseClass.isNested())
                nfields--;
            if (vthis2 && !(cd && cd.baseClass && cd.baseClass.vthis2))
                nfields--;
        }
        bool errors = false;

        // Fill in missing any elements with default initializers
        foreach (i; 0 .. nfields)
        {
            auto vd = fields[i];
            if (vd.errors)
            {
                errors = true;
                continue;
            }

            const vdIsVoidInit = vd._init && vd._init.isVoidInitializer();

            // Find overlapped fields with the hole [vd.offset .. vd.offset.size()].
            foreach (j; 0 .. nfields)
            {
                if (i == j)
                    continue;
                auto v2 = fields[j];
                if (v2.errors)
                {
                    errors = true;
                    continue;
                }
                if (!vd.isOverlappedWith(v2))
                    continue;

                // vd and v2 are overlapping.
                vd.overlapped = true;
                v2.overlapped = true;

                if (!MODimplicitConv(vd.type.mod, v2.type.mod))
                    v2.overlapUnsafe = true;
                if (!MODimplicitConv(v2.type.mod, vd.type.mod))
                    vd.overlapUnsafe = true;

                if (i > j)
                    continue;

                if (!v2._init)
                    continue;

                if (v2._init.isVoidInitializer())
                    continue;

                if (vd._init && !vdIsVoidInit && v2._init)
                {
                    .error(loc, "overlapping default initialization for field `%s` and `%s`", v2.toChars(), vd.toChars());
                    errors = true;
                }
                else if (v2._init && i < j)
                {
                    // @@@DEPRECATED_v2.086@@@.
                    .deprecation(v2.loc, "union field `%s` with default initialization `%s` must be before field `%s`",
                        v2.toChars(), v2._init.toChars(), vd.toChars());
                    //errors = true;
                }
            }
        }
        return errors;
    }

    /***************************************
     * Fill out remainder of elements[] with default initializers for fields[].
     * Params:
     *      loc         = location
     *      elements    = explicit arguments which given to construct object.
     *      ctorinit    = true if the elements will be used for default initialization.
     * Returns:
     *      false if any errors occur.
     *      Otherwise, returns true and the missing arguments will be pushed in elements[].
     */
    final bool fill(Loc loc, Expressions* elements, bool ctorinit)
    {
        //printf("AggregateDeclaration::fill() %s\n", toChars());
        assert(sizeok == Sizeok.done);
        assert(elements);
        const nfields = nonHiddenFields();
        bool errors = false;

        size_t dim = elements.dim;
        elements.setDim(nfields);
        foreach (size_t i; dim .. nfields)
            (*elements)[i] = null;

        // Fill in missing any elements with default initializers
        foreach (i; 0 .. nfields)
        {
            if ((*elements)[i])
                continue;

            auto vd = fields[i];
            auto vx = vd;
            if (vd._init && vd._init.isVoidInitializer())
                vx = null;

            // Find overlapped fields with the hole [vd.offset .. vd.offset.size()].
            size_t fieldi = i;
            foreach (j; 0 .. nfields)
            {
                if (i == j)
                    continue;
                auto v2 = fields[j];
                if (!vd.isOverlappedWith(v2))
                    continue;

                if ((*elements)[j])
                {
                    vx = null;
                    break;
                }
                if (v2._init && v2._init.isVoidInitializer())
                    continue;

                version (all)
                {
                    /* Prefer first found non-void-initialized field
                     * union U { int a; int b = 2; }
                     * U u;    // Error: overlapping initialization for field a and b
                     */
                    if (!vx)
                    {
                        vx = v2;
                        fieldi = j;
                    }
                    else if (v2._init)
                    {
                        .error(loc, "overlapping initialization for field `%s` and `%s`", v2.toChars(), vd.toChars());
                        errors = true;
                    }
                }
                else
                {
                    // fixes https://issues.dlang.org/show_bug.cgi?id=1432 by enabling this path always

                    /* Prefer explicitly initialized field
                     * union U { int a; int b = 2; }
                     * U u;    // OK (u.b == 2)
                     */
                    if (!vx || !vx._init && v2._init)
                    {
                        vx = v2;
                        fieldi = j;
                    }
                    else if (vx != vd && !vx.isOverlappedWith(v2))
                    {
                        // Both vx and v2 fills vd, but vx and v2 does not overlap
                    }
                    else if (vx._init && v2._init)
                    {
                        .error(loc, "overlapping default initialization for field `%s` and `%s`",
                            v2.toChars(), vd.toChars());
                        errors = true;
                    }
                    else
                        assert(vx._init || !vx._init && !v2._init);
                }
            }
            if (vx)
            {
                Expression e;
                if (vx.type.size() == 0)
                {
                    e = null;
                }
                else if (vx._init)
                {
                    assert(!vx._init.isVoidInitializer());
                    if (vx.inuse)   // https://issues.dlang.org/show_bug.cgi?id=18057
                    {
                        vx.error(loc, "recursive initialization of field");
                        errors = true;
                    }
                    else
                        e = vx.getConstInitializer(false);
                }
                else
                {
                    if ((vx.storage_class & STC.nodefaultctor) && !ctorinit)
                    {
                        .error(loc, "field `%s.%s` must be initialized because it has no default constructor",
                            type.toChars(), vx.toChars());
                        errors = true;
                    }
                    /* https://issues.dlang.org/show_bug.cgi?id=12509
                     * Get the element of static array type.
                     */
                    Type telem = vx.type;
                    if (telem.ty == Tsarray)
                    {
                        /* We cannot use Type::baseElemOf() here.
                         * If the bottom of the Tsarray is an enum type, baseElemOf()
                         * will return the base of the enum, and its default initializer
                         * would be different from the enum's.
                         */
                        while (telem.toBasetype().ty == Tsarray)
                            telem = (cast(TypeSArray)telem.toBasetype()).next;
                        if (telem.ty == Tvoid)
                            telem = Type.tuns8.addMod(telem.mod);
                    }
                    if (telem.needsNested() && ctorinit)
                        e = telem.defaultInit(loc);
                    else
                        e = telem.defaultInitLiteral(loc);
                }
                (*elements)[fieldi] = e;
            }
        }
        foreach (e; *elements)
        {
            if (e && e.op == TOK.error)
                return false;
        }

        return !errors;
    }

    /****************************
     * Do byte or word alignment as necessary.
     * Align sizes of 0, as we may not know array sizes yet.
     * Params:
     *   alignment = struct alignment that is in effect
     *   size = alignment requirement of field
     *   poffset = pointer to offset to be aligned
     */
    extern (D) static void alignmember(structalign_t alignment, uint size, uint* poffset) pure nothrow @safe
    {
        //printf("alignment = %d, size = %d, offset = %d\n",alignment,size,offset);
        switch (alignment)
        {
        case cast(structalign_t)1:
            // No alignment
            break;

        case cast(structalign_t)STRUCTALIGN_DEFAULT:
            // Alignment in Target::fieldalignsize must match what the
            // corresponding C compiler's default alignment behavior is.
            assert(size > 0 && !(size & (size - 1)));
            *poffset = (*poffset + size - 1) & ~(size - 1);
            break;

        default:
            // Align on alignment boundary, which must be a positive power of 2
            assert(alignment > 0 && !(alignment & (alignment - 1)));
            *poffset = (*poffset + alignment - 1) & ~(alignment - 1);
            break;
        }
    }

    /****************************************
     * Place a member (mem) into an aggregate (agg), which can be a struct, union or class
     * Returns:
     *      offset to place field at
     *
     * nextoffset:    next location in aggregate
     * memsize:       size of member
     * memalignsize:  natural alignment of member
     * alignment:     alignment in effect for this member
     * paggsize:      size of aggregate (updated)
     * paggalignsize: alignment of aggregate (updated)
     * isunion:       the aggregate is a union
     */
    extern (D) static uint placeField(uint* nextoffset, uint memsize, uint memalignsize,
        structalign_t alignment, uint* paggsize, uint* paggalignsize, bool isunion)
    {
        uint ofs = *nextoffset;

        const uint actualAlignment =
            alignment == STRUCTALIGN_DEFAULT ? memalignsize : alignment;

        // Ensure no overflow
        bool overflow;
        const sz = addu(memsize, actualAlignment, overflow);
        addu(ofs, sz, overflow);
        if (overflow) assert(0);

        alignmember(alignment, memalignsize, &ofs);
        uint memoffset = ofs;
        ofs += memsize;
        if (ofs > *paggsize)
            *paggsize = ofs;
        if (!isunion)
            *nextoffset = ofs;

        if (*paggalignsize < actualAlignment)
            *paggalignsize = actualAlignment;

        return memoffset;
    }

    override final Type getType()
    {
        return type;
    }

    // is aggregate deprecated?
    override final bool isDeprecated() const
    {
        return !!(this.storage_class & STC.deprecated_);
    }

    /// Flag this aggregate as deprecated
    final void setDeprecated()
    {
        this.storage_class |= STC.deprecated_;
    }

    /****************************************
     * Returns true if there's an extra member which is the 'this'
     * pointer to the enclosing context (enclosing aggregate or function)
     */
    final bool isNested() const
    {
        return enclosing !is null;
    }

    /* Append vthis field (this.tupleof[$-1]) to make this aggregate type nested.
     */
    extern (D) final void makeNested()
    {
        if (enclosing) // if already nested
            return;
        if (sizeok == Sizeok.done)
            return;
        if (isUnionDeclaration() || isInterfaceDeclaration())
            return;
        if (storage_class & STC.static_)
            return;

        // If nested struct, add in hidden 'this' pointer to outer scope
        auto s = toParentLocal();
        if (!s)
            s = toParent2();
        if (!s)
            return;
        Type t = null;
        if (auto fd = s.isFuncDeclaration())
        {
            enclosing = fd;

            /* https://issues.dlang.org/show_bug.cgi?id=14422
             * If a nested class parent is a function, its
             * context pointer (== `outer`) should be void* always.
             */
            t = Type.tvoidptr;
        }
        else if (auto ad = s.isAggregateDeclaration())
        {
            if (isClassDeclaration() && ad.isClassDeclaration())
            {
                enclosing = ad;
            }
            else if (isStructDeclaration())
            {
                if (auto ti = ad.parent.isTemplateInstance())
                {
                    enclosing = ti.enclosing;
                }
            }
            t = ad.handleType();
        }
        if (enclosing)
        {
            //printf("makeNested %s, enclosing = %s\n", toChars(), enclosing.toChars());
            assert(t);
            if (t.ty == Tstruct)
                t = Type.tvoidptr; // t should not be a ref type

            assert(!vthis);
            vthis = new ThisDeclaration(loc, t);
            //vthis.storage_class |= STC.ref_;

            // Emulate vthis.addMember()
            members.push(vthis);

            // Emulate vthis.dsymbolSemantic()
            vthis.storage_class |= STC.field;
            vthis.parent = this;
            vthis.protection = Prot(Prot.Kind.public_);
            vthis.alignment = t.alignment();
            vthis.semanticRun = PASS.semanticdone;

            if (sizeok == Sizeok.fwd)
                fields.push(vthis);

            makeNested2();
        }
    }

    /* Append vthis2 field (this.tupleof[$-1]) to add a second context pointer.
     */
    extern (D) final void makeNested2()
    {
        if (vthis2)
            return;
        if (!vthis)
            makeNested();   // can't add second before first
        if (!vthis)
            return;
        if (sizeok == Sizeok.done)
            return;
        if (isUnionDeclaration() || isInterfaceDeclaration())
            return;
        if (storage_class & STC.static_)
            return;

        auto s0 = toParentLocal();
        auto s = toParent2();
        if (!s || !s0 || s == s0)
            return;
        auto cd = s.isClassDeclaration();
        Type t = cd ? cd.type : Type.tvoidptr;

        vthis2 = new ThisDeclaration(loc, t);
        //vthis2.storage_class |= STC.ref_;

        // Emulate vthis2.addMember()
        members.push(vthis2);

        // Emulate vthis2.dsymbolSemantic()
        vthis2.storage_class |= STC.field;
        vthis2.parent = this;
        vthis2.protection = Prot(Prot.Kind.public_);
        vthis2.alignment = t.alignment();
        vthis2.semanticRun = PASS.semanticdone;

        if (sizeok == Sizeok.fwd)
            fields.push(vthis2);
    }

    override final bool isExport() const
    {
        return protection.kind == Prot.Kind.export_;
    }

    /*******************************************
     * Look for constructor declaration.
     */
    final Dsymbol searchCtor()
    {
        auto s = search(Loc.initial, Id.ctor);
        if (s)
        {
            if (!(s.isCtorDeclaration() ||
                  s.isTemplateDeclaration() ||
                  s.isOverloadSet()))
            {
                s.error("is not a constructor; identifiers starting with `__` are reserved for the implementation");
                errors = true;
                s = null;
            }
        }
        if (s && s.toParent() != this)
            s = null; // search() looks through ancestor classes
        if (s)
        {
            // Finish all constructors semantics to determine this.noDefaultCtor.
            struct SearchCtor
            {
                extern (C++) static int fp(Dsymbol s, void* ctxt)
                {
                    auto f = s.isCtorDeclaration();
                    if (f && f.semanticRun == PASS.init)
                        f.dsymbolSemantic(null);
                    return 0;
                }
            }

            for (size_t i = 0; i < members.dim; i++)
            {
                auto sm = (*members)[i];
                sm.apply(&SearchCtor.fp, null);
            }
        }
        return s;
    }

    override final Prot prot() pure nothrow @nogc @safe
    {
        return protection;
    }

    // 'this' type
    final Type handleType()
    {
        return type;
    }

    // Back end
    Symbol* stag;   /// tag symbol for debug data
    Symbol* sinit;  /// initializer symbol

    override final inout(AggregateDeclaration) isAggregateDeclaration() inout
    {
        return this;
    }

    override void accept(Visitor v)
    {
        v.visit(this);
    }
}
