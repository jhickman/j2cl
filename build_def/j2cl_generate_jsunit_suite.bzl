"""j2cl_generate_jsunit_suite build macro

Takes Java source that contains JUnit tests and translates it into a goog.testing.testSuite.


Example using a jsunit_test:

j2cl_library(
    name = "mytests",
    ...
)

j2cl_generate_jsunit_suite(
    name = "CodeGen",
    deps = [":mytests"],
    test_class = "mypackage.MyTest",
)

jsunit_test(
  name = "test",
  srcs = [":CodeGen.js.zip"],
  deps = [":CodeGen"],
  ...
)

"""


load("//third_party/java/j2cl:j2cl_library.bzl", "j2cl_library")
load("//build_def:j2cl_util.bzl", "get_java_package")

_TEMPLATE = """
// THIS IS GENERATED CODE. DO NOT EDIT.
// GENERATED FROM //%s/BUILD (target: %s)

package %s;

import com.google.j2cl.junit.apt.J2clTestInput;

/**
 * J2CL java tests.
 *
 * @author generated by j2cl_generate_jsunit_suite.bzl.
 */
@J2clTestInput(%s.class)
public class %s {}
"""

def _generate_test_input(name, test_class):
  java_package = get_java_package(PACKAGE_NAME) or "_default_"
  java_class = name.replace('-', '_').title() + "__generated_j2cl_test_input"
  java_code = _TEMPLATE % (PACKAGE_NAME, name, java_package, test_class, java_class)

  native.genrule(
      name = java_class,
      outs = [java_class + ".java"],
      cmd="echo \"%s\" > $@" % java_code,
      tags=["manual", "no_tap"],
      testonly = 1,
  )

  return java_class + ".java"


def j2cl_generate_jsunit_suite(name, test_class, deps, tags = []):
  """Macro for cross compiling a JUnit Suite to JavaScript testSuite"""

  test_input = _generate_test_input(name, test_class)
  # This target triggers our Java annotation processor and generates the
  # plumbing between a jsunit_test and transpiled JUnit tests
  # It's outputs are:
  #  - test_summary.json that lists all jsunit test suites
  #  - A JavaScript file for every JUnit test containing a jsunit tests suite
  #  - A Java class (JsType) that contains the bridge between the jsunit test
  #        suite and the JUnit test. This is being used from the JavaScript
  #        file.
  #
  # We separated this out into a separate target so we can have dependencies
  # here that users might not have in their tests (e.g. jsinterop annotations).
  # We need the extra dep here on user provided dependencies since our generated
  # code refers to user written code (test cases).
  j2cl_library(
      name = name,
      srcs = [test_input],
      deps = deps +  [
          "//third_party/java/j2cl:internal_junit_annotations",
          "//third_party/java/gwt:gwt-jsinterop-annotations-j2cl",
      ],
      _js_deps = ["//javascript/closure/testing:testcase"],
      plugins = ["//third_party/java/j2cl:junit_processor"],
      testonly = 1,
      tags = tags,
      generate_build_test=False,
  )

  # The Java annotation processor on the above target generates jsunit suites
  # (JavaScript files), but the same jar file also contains unrelated things
  # (e.g. class files), this genrules takes the jar file as input and creates
  # a new zip file that only contains the generated javascript (jsunit test
  # suites) and the test_summary.json file.
  # This is the format that jsunit_test will later expect.
  out_jar = ":lib" + name + "_java_library.jar"
  native.genrule(
      name=name + "_transpile_gen",
      outs=[name + ".js.zip"],
      cmd="\n".join([
          "unzip -q $(location %s) *.js *.json -d zip_out/" % out_jar,
          "cd zip_out/",
          "zip -q -r ../$@ .",
      ]),
      testonly=1,
      tags=["manual", "no_tap"],
      tools=[out_jar],
  )
