Basic :: #import "Basic";
Compiler :: #import "Compiler";
File :: #import "File";
String :: #import "String";
MetaprogramPlugins :: #import "Metaprogram_Plugins";

dummy_ide_check_message :: (message : *Compiler.Message) {
}

#run () {
    Basic.set_working_directory(String.join(#filepath, "/.."));
    File.make_directory_if_it_does_not_exist("./bin");

    workspace := Compiler.compiler_create_workspace("sloubi-chess");

    options := Compiler.get_build_options();
    options.output_executable_name  = "sloubi-chess";
    options.output_path             = String.join(#filepath, "/../bin/");
    options.optimization_level      = .DEBUG;
    options.text_output_flags       = .OUTPUT_TIMING_INFO; // @note And not the linker lines.
    options.backend = .LLVM;

    arguments := options.compile_time_command_line;
    if arguments.count > 0 && (arguments[0] == "release" || arguments[0] == "ship") {
        Basic.log("Building release...");
        if arguments[0] == "ship" then options.text_output_flags = 0;
        options.optimization_level = .RELEASE;
        options.backend = .X64;
    }

    import_path: [..] string;
    Basic.array_add(*import_path, "./lava/bindings");
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
            Basic.array_add(*arguments, "-rpath='$ORIGIN/../lava/bindings/Vulkan'");
        }

        options.additional_linker_arguments = arguments;
    }

    // Building our main program
    Compiler.set_build_options(options, workspace);

    plugins : [..]*Compiler.Metaprogram_Plugin;
    MetaprogramPlugins.init_plugins(.["Sill/plugin"], *plugins, workspace);

    for plugin : plugins if plugin.before_intercept then plugin.before_intercept(plugin);

    Compiler.compiler_begin_intercept(workspace);
    Compiler.add_build_file("./src/main.jai", workspace);

    for plugin : plugins if plugin.add_source then plugin.add_source(plugin);

    ide_check_message := dummy_ide_check_message;
    if options.user_data_u64 {
        ide_check_message = << cast(*type_of(dummy_ide_check_message)) options.user_data_u64;
        options.output_type = .NO_OUTPUT;
    }

    while true {
        message := Compiler.compiler_wait_for_message();
        if !message then break;
        if message.workspace != workspace then continue;

        ide_check_message(message);
        for plugin : plugins if plugin.message then plugin.message(plugin, message);

        if message.kind == .COMPLETE then break;
    }

    Compiler.compiler_end_intercept(workspace);

    for plugin : plugins if plugin.finish then plugin.finish(plugin);
    for plugin : plugins if plugin.shutdown then plugin.shutdown(plugin);

    // Do not generate executable for this build program
    Compiler.set_build_options_dc(.{ do_output = false });
}();
