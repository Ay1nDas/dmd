module dmd.compiler.performance_test.compile_time.large_test;

import std.stdio;
import std.meta;
import std.string;
import std.conv;
import std.algorithm;
import std.traits;

// ------------------------
// 1. Deep Recursive Template
// ------------------------
template RecursiveTemplate(int N)
{
    static if (N == 0)
        enum RecursiveTemplate = 0;
    else
        enum RecursiveTemplate = RecursiveTemplate!(N - 1) + 1;
}

// ------------------------
// 2. Compile-Time Generated Mixin
// ------------------------
string generateFunctions(int count)
{
    string result;
    foreach (i; 0 .. count)
    {
        result ~= "int func" ~ i.to!string ~ "() { return " ~ i.to!string ~ "; }\n";
    }
    return result;
}

mixin(generateFunctions(500)); // Increase function count

// ------------------------
// 3. CTFE-Heavy Fibonacci
// ------------------------
int computeCTFE(int n)
{
    if (n <= 1) return 1;
    return computeCTFE(n - 1) + computeCTFE(n - 2);
}

// ------------------------
// 4. Deep Static If Nesting
// ------------------------
template DeepStaticIf(int N)
{
    static if (N <= 0)
        enum DeepStaticIf = "done";
    else static if (N % 2 == 0)
        enum DeepStaticIf = DeepStaticIf!(N - 1);
    else
        enum DeepStaticIf = DeepStaticIf!(N - 2);
}

// ------------------------
// 5. Massive Enum
// ------------------------
enum HugeEnum =
({
    int result = 0;
    foreach (i; 0 .. 10_000)
        result += i * 3;
    return result;
})();

// ------------------------
// 6. Static Foreach Generation
// ------------------------
mixin template GenerateStructs(int N)
{
    static foreach (i; 0 .. N)
    {
        mixin("struct Struct" ~ i.to!string ~ " { int x = " ~ i.to!string ~ "; }");
    }
}

mixin GenerateStructs!300; // Generate 300 structs at compile time

// ------------------------
// 7. Template Mixin Nesting
// ------------------------
template NestedTemplate(int N)
{
    static if (N <= 0)
        enum NestedTemplate = 1;
    else
        enum NestedTemplate = NestedTemplate!(N - 1) * 2;
}

mixin template RecursiveMixins(int N)
{
    static foreach (i; 0 .. N)
    {
        mixin("enum temp_" ~ i.to!string ~ " = NestedTemplate!(10);");
    }
}

mixin RecursiveMixins!100;

// ------------------------
// 8. Traits and Introspection
// ------------------------
template DumpTraits(T)
{
    enum DumpTraits = T.stringof ~ ": " ~
        (isIntegral!T ? "Integral" : "Not Integral");
}

enum traitsResult = DumpTraits!(int);
enum traitsResult2 = DumpTraits!(string);

// ------------------------
// 9. Complex Nested Types
// ------------------------
struct ComplexType
{
    union {
        struct { int x; double y; }
        int[100] z;
    }
    static if (true)
    {
        int extra = RecursiveTemplate!(100);
    }
}

// ------------------------
// Main Entry Point
// ------------------------
void main()
{
    {
        enum fib = computeCTFE(50); // Very slow at compile time
        writeln("CTFE Fib(35): ", fib);

        enum val = RecursiveTemplate!(100); // Deep template recursion
        writeln("RecursiveTemplate(1500): ", val);

        writeln("DeepStaticIf(1000): ", DeepStaticIf!(100));
        writeln("HugeEnum: ", HugeEnum);
        writeln("Trait Check: ", traitsResult, " | ", traitsResult2);
        writeln("NestedTemplate: ", NestedTemplate!(15));
    }
}
