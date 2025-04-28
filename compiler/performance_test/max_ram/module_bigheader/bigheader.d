module dmd.compiler.performance_test.max_ram.module_bigheader.bigheader;

// bigheader.d
import std.conv;

// Recursive template to generate deeply nested structs
template MegaStruct(int N)
{
    static if (N <= 0)
        alias MegaStruct = void;
    else
        struct MegaStruct
        {
            static if (N > 1)
                MegaStruct!(N - 1) child;

            enum value = N;
        }
}

// Mixin template generating many enum members to bloat symbol table
mixin template RepeatedMixins(int N)
{
    static foreach (i; 0 .. N)
    {
        mixin("enum val" ~ to!string(i) ~ " = " ~ to!string(i) ~ ";");
    }
}

// Recursively alias many template instantiations
template GenerateTemplates(int N)
{
    static if (N > 0)
    {
        mixin("alias GenTemp" ~ to!string(N) ~ " = MegaStruct!(" ~ to!string(N) ~ ");");
        mixin GenerateTemplates!(N - 1);
    }
}

// Simulate repetitive imports and aliasing
template ImportFlood(int N)
{
    static if (N > 0)
    {
        mixin("alias Dummy" ~ to!string(N) ~ " = MegaStruct!(" ~ to!string(N) ~ ");");
        mixin ImportFlood!(N - 1);
    }
}