Basic :: #import "Basic";
Compiler :: #import "Compiler";
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
    Basic.array_add(*import_path, "./lava/modules");
    Basic.array_add(*import_path, ..options.import_path);
    options.import_path = import_path;

    Compiler.set_build_options(options, workspace);
    Compiler.add_build_file("./src/second.jai", workspace);
    Compiler.set_build_options_dc(.{ do_output = false });
}();
