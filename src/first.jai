Basic :: #import "Basic";
Compiler :: #import "Compiler";
File :: #import "File";
FileUtilities :: #import "File_Utilities";
Process :: #import "Process";
String :: #import "String";

#run () {
    Basic.set_working_directory(String.join(#filepath, "/.."));
    workspace := Compiler.compiler_create_workspace("sloubi-chess-preparation");

    // Can't use the Sill plugin in second.jai if the import path
    // is not known, and I don't want users to have to specify -import_dir.
    // So, yeah, this whole file and metaprogram is there just to set one import path.
    // The real work is done in second.jai.
    options := Compiler.get_build_options();
    import_path: [..] string;
    Basic.array_add(*import_path, ..options.import_path);
    Basic.array_add(*import_path, "../lava/modules");
    options.import_path = import_path;
    options.intermediate_path = String.join(#filepath, "/../.build/");

    Compiler.set_build_options(options, workspace);
    Compiler.compiler_begin_intercept(workspace);
    Compiler.add_build_file("./second.jai", workspace);

    while true {
        message := Compiler.compiler_wait_for_message();
        if !message then break;
        if message.kind == .COMPLETE then break;
    }

    Compiler.compiler_end_intercept(workspace);

    arguments := options.compile_time_command_line;
    if arguments.count > 0 && arguments[0] == "ship" {
        ship();
    }

    Compiler.set_build_options_dc(.{ do_output = false });
}();

ship :: () {
    Basic.log("Fetching tags...");
    Process.run_command("git", "fetch", "--tags");
    _, output := Process.run_command("git", "tag", capture_and_return_output = true);
    versions := String.split(String.trim_right(output, "\n"), "\n");
    lastVersionParts := String.split(Basic.peek(versions), ".");
    Basic.peek_pointer(lastVersionParts).* = Basic.tprint("%", Basic.string_to_int(Basic.peek(lastVersionParts)) + 1);
    newVersion := String.join(..lastVersionParts, separator = ".");

    folder := Basic.tprint("releases/sloubi-chess-%-%", newVersion, ifx OS == .WINDOWS then "win64" else "linux64");
    Basic.log("Releasing to '%'...", folder);

    File.make_directory_if_it_does_not_exist("releases");
    File.make_directory_if_it_does_not_exist(folder);

    #if OS == .WINDOWS {
        FileUtilities.copy_file("sloubi-chess.exe", Basic.tprint("%/sloubi-chess.exe", folder));
        FileUtilities.copy_file("lava/bindings/Shaderc/libshaderc.dll", Basic.tprint("%/libshaderc.dll", folder));
        FileUtilities.copy_file("lava/bindings/StbTrueType/libstbtruetype.dll",  Basic.tprint("%/libstbtruetype.dll", folder));
        FileUtilities.copy_file("lava/bindings/Vulkan/libvulkan.dll",  Basic.tprint("%/libvulkan.dll", folder));
        // FileUtilities.copy_file("lava/bindings/Vulkan/layers/win64/libVkLayer_khronos_shader_object.json",  Basic.tprint("%/libVkLayer_khronos_shader_object.json", folder));
        // FileUtilities.copy_file("lava/bindings/Vulkan/layers/win64/libVkLayer_khronos_shader_object.dll",  Basic.tprint("%/libVkLayer_khronos_shader_object.dll", folder));
        FileUtilities.copy_file("lava/bindings/VulkanMemoryAllocator/libvma.dll",  Basic.tprint("%/libvma.dll", folder));
    } else {
        POSIX :: #import "POSIX";
        File.make_directory_if_it_does_not_exist(Basic.tprint("%/lib", folder));
        FileUtilities.copy_file("sloubi-chess", Basic.tprint("%/sloubi-chess", folder));
        POSIX.chmod(Basic.tprint("%/sloubi-chess\0", folder).data, 0x1FF); // Executable
        FileUtilities.copy_file("lava/bindings/Shaderc/libshaderc.so", Basic.tprint("%/lib/libshaderc.so", folder));
        FileUtilities.copy_file("lava/bindings/StbTrueType/libstbtruetype.so",  Basic.tprint("%/lib/libstbtruetype.so", folder));
        FileUtilities.copy_file("lava/bindings/Vulkan/libvulkan.so",  Basic.tprint("%/lib/libvulkan.so", folder));
        // FileUtilities.copy_file("lava/bindings/Vulkan/layers/linux/libVkLayer_khronos_shader_object.json",  Basic.tprint("%/lib/libVkLayer_khronos_shader_object.json", folder));
        // FileUtilities.copy_file("lava/bindings/Vulkan/layers/linux/libVkLayer_khronos_shader_object.so",  Basic.tprint("%/lib/libVkLayer_khronos_shader_object.so", folder));
        FileUtilities.copy_file("lava/bindings/VulkanMemoryAllocator/libvma.so",  Basic.tprint("%/lib/libvma.so", folder));
    }

    File.make_directory_if_it_does_not_exist(Basic.tprint("%/assets", folder));
    FileUtilities.visit_files("assets", true, *folder, (info : *FileUtilities.File_Visit_Info, folder : *string) {
        if info.is_symlink then return;
        targetFileName := Basic.tprint("%/%", folder.*, info.full_name);
        if info.is_directory {
            File.make_directory_if_it_does_not_exist(targetFileName);
        } else {
            FileUtilities.copy_file(info.full_name, targetFileName);
        }
    }, visit_directories = true, follow_symlinks = false);
}
