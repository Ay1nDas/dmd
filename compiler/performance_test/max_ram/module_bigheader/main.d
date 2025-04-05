module dmd.compiler.performance_test.max_ram.module_bigheader.main;

// main.d
import std.stdio;
import std.conv;
import bigheader;

mixin GenerateTemplates!(300);
mixin RepeatedMixins!(50_000);
mixin ImportFlood!(300);

void main() {
    writeln("Compile-time heavy file loaded.");
}