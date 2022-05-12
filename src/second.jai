Basic :: #import "Basic";
Compiler :: #import "Compiler";
File :: #import "File";
String :: #import "String";
MetaprogramPlugins :: #import "Metaprogram_Plugins";

#run () {
    Basic.set_working_directory(String.join(#filepath, "/.."));
    File.make_directory_if_it_does_not_exist("./bin");

    workspace := Compiler.compiler_create_workspace("sloubi-chess");

    options := Compiler.get_build_options();
    options.output_executable_name  = "sloubi-chess";
    options.output_path             = String.join(#filepath, "/../bin/");
    options.optimization_level      = .DEBUG;
    options.text_output_flags       = .OUTPUT_TIMING_INFO; // @note And not the linker lines.

    arguments := options.compile_time_command_line;
    if arguments.count > 0 && arguments[0] == "release" {
        Basic.log("Building RELEASE.");
        options.optimization_level = .RELEASE;
    }

    import_path: [..] string;
    Basic.array_add(*import_path, "./lava/bindings");
    Basic.array_add(*import_path, "./lava/modules");
    Basic.array_add(*import_path, ..options.import_path);
    options.import_path = import_path;

    if options.os_target == .WINDOWS {
        // @note Remove the console, tell the linker it's a window application.
        // And also remove the need for the WinMain...
        // (From https://stackoverflow.com/a/5260237)
        options.additional_linker_arguments = .["/subsystem:windows ", "/entry:mainCRTStartup"];
    } else {
        arguments: [..] string;
        Basic.array_add(*arguments, "-rpath='$ORIGIN/lib'");

        if options.optimization_level == .DEBUG {
            Basic.array_add(*arguments, "-rpath='$ORIGIN/../lava/bindings/Shaderc'");
            Basic.array_add(*arguments, "-rpath='$ORIGIN/../lava/bindings/StbTrueType'");
            Basic.array_add(*arguments, "-rpath='$ORIGIN/../lava/bindings/Xcb'"); // For libxcbglue.so
            Basic.array_add(*arguments, "-rpath='$ORIGIN/../lava/bindings/Vulkan'");
        }

        options.additional_linker_arguments = arguments;
    }

    // Building our main program
    Compiler.set_build_options(options, workspace);

    plugins : [..]*Compiler.Metaprogram_Plugin;
    MetaprogramPlugins.init_plugins(.["Sill/plugin"], *plugins, workspace);

    Compiler.compiler_begin_intercept(workspace);
    Compiler.add_build_file("./src/main.jai", workspace);

    while true {
        message := Compiler.compiler_wait_for_message();
        if !message then break;
        if message.workspace != workspace then continue;

        for plugin : plugins if plugin.message plugin.message(plugin, message);

        if message.kind == .COMPLETE then break;
    }

    Compiler.compiler_end_intercept(workspace);

    // Do not generate executable for this build program
    Compiler.set_build_options_dc(.{ do_output = false });
}();
