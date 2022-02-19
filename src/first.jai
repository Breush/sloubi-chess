Basic :: #import "Basic";
Compiler :: #import "Compiler";
File :: #import "File";
String :: #import "String";

#run () {
    Basic.set_working_directory(String.join(#filepath, "/.."));
    File.make_directory_if_it_does_not_exist("./bin");

    workspace := Compiler.compiler_create_workspace("sloubi-chess");

    options := Compiler.get_build_options();
    options.output_executable_name  = "sloubi-chess";
    options.output_path             = String.join(#filepath, "/../bin/");
    options.optimization_level      = .DEBUG;
    options.text_output_flags       = .OUTPUT_TIMING_INFO; // @note And not the linker lines.

    import_path: [..] string;
    Basic.array_add(*import_path, "./lava/bindings");
    Basic.array_add(*import_path, "./lava/modules");
    Basic.array_add(*import_path, ..options.import_path);
    options.import_path = import_path;

    if options.os_target == .LINUX { // @todo Should be done only in DEBUG mode, otherwise the paths will be wrong
        arguments: [..] string;
        Basic.array_add(*arguments, "-rpath=$ORIGIN");
        Basic.array_add(*arguments, Basic.tprint("-rpath=%../lava/bindings/Shaderc", #filepath));
        Basic.array_add(*arguments, Basic.tprint("-rpath=%../lava/bindings/Xcb", #filepath));
        options.additional_linker_arguments = arguments;
    }

    // Building our main program
    Compiler.set_build_options(options, workspace);

    // Compiler.compiler_begin_intercept(workspace);
    Compiler.add_build_file("./src/main.jai", workspace);
    // while Compiler.compiler_wait_for_message() {};
    // Compiler.compiler_end_intercept(workspace);

    // Do not generate executable for this build program
    Compiler.set_build_options_dc(.{ do_output = false });
}();
