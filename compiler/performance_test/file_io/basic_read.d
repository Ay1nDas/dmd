module dmd.compiler.performance_test.file_io.basic_read;

import std.stdio;
import std.string;
import std.conv;

void main() {
    auto file = File("input.txt", "r");

    foreach (line; file.byLine()) {
        auto cleanLine = line.strip();
        if (cleanLine.length == 0) continue;

        // Convert to integer, float, etc.
        int x = to!int(cleanLine);
        writeln("Parsed int: ", x);
    }
}