module dmd.compiler.test.fail_compilation.test21215;

/* TEST_OUTPUT:
---
fail_compilation/test21215.d(15): Error: `y` is not a member of `S`
fail_compilation/test21215.d(20): Error: `xhs` is not a member of `S`, did you mean variable `xsh`?
fail_compilation/test21215.d(30): Error: `y` is not a member of `S`
fail_compilation/test21215.d(34): Error: `yashu` is not a member of `S`
---
*/
struct S { int xsh; }

void test() {
	auto s = S(
		y:
    1
	);

  auto s3 = S(
    xhs:
    1
  );

  auto s4 = S(
    xsh: 1
  );

  auto s6 = S(
    xsh: 1,
    y: 2
  );

  auto s7 = S(
    yashu:
    

    2

  );
}