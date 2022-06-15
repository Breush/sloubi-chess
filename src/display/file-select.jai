FileSelectEntity :: struct {
    using entity : Sill.Entity;

    ui : Sill.UiComponent;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;

    currentPath : string;

    extensionFilter : string;
    callback : FileSelectedCallback;

    FileSelectedCallback :: #type (selectedFile : string) -> ();

    on_cleanup :: (using this : *FileSelectEntity) {
        Basic.free(currentPath);
    }
}

Entries :: struct {
    directories : [..] string;
    files : [..] string;
};

EntryEntity :: struct {
    using entity : Sill.Entity;

    ui : Sill.UiComponent;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;

    isDirectory : bool;
    fileOrDirectoryName : string;

    on_cleanup :: (using this : *EntryEntity) {
        Basic.free(fileOrDirectoryName);
    }
}

file_select_show :: (extensionFilter : string, callback : FileSelectEntity.FileSelectedCallback) {
    fileSelect := SillMeta.create_file_select_entity(instance.engine);
    fileSelect.extensionFilter = extensionFilter;
    fileSelect.callback = callback;
    instance.fileSelect = fileSelect;

    mesh := create_text_mesh();
    Basic.array_add(*fileSelect.mesh.nodes, .{});
    Basic.array_add(*fileSelect.mesh.nodes[0].primitives, mesh);

    charInfos := text_mesh_update(mesh, Basic.tprint("Select a % file", extensionFilter), *instance.fonts.bold, *instance.config.env.textColor);
    Basic.array_free(charInfos);

    Sill.ui_on_update(*fileSelect.ui, (update : Sill.UiUpdate, fileSelect : *FileSelectEntity) {
        _place_children(fileSelect);
    }, .Child, fileSelect);

    path : string;
    if instance.persistence.fileSelect.lastPath.count != 0 {
        path = Basic.copy_string(instance.persistence.fileSelect.lastPath);
    } else {
        path = Chamber.os_user_path();
    }
    _show_path(path);

    file_select_reflow();
}

file_select_reflow :: () {
    fileSelect := instance.fileSelect;
    if fileSelect == null then return;

    extent := Crater.window_get_extent(instance.engine.window);

    fileSelect.transform.translation.x = UiConstants.PaddingHorizontal;
    fileSelect.transform.translation.y = - cast(s32) extent.height / 2 + UiConstants.PaddingVertical;
    fileSelect.ui.extent.width = extent.width - 2 * UiConstants.PaddingHorizontal;
    fileSelect.ui.extent.height = extent.height - 2 * UiConstants.PaddingVertical;
    fileSelect.ui.anchor = .TopLeft;

    Sill.transform_commit(*fileSelect.transform);
}

#scope_file

_go_into_directory :: (directoryName : string) {
    _show_path(Basic.sprint("%/%", instance.fileSelect.currentPath, directoryName));
}

_show_path :: (path : string) {
    // Removing old entries...
    for child : instance.fileSelect.children {
        Sill.destroy_entity(child, warnParent = false);
    }
    instance.fileSelect.children.count = 0;

    Basic.free(instance.fileSelect.currentPath);
    instance.fileSelect.currentPath = path;

    entries : Entries;
    defer { Basic.array_free(entries.files); Basic.array_free(entries.directories); }
    Basic.array_add(*entries.directories, Basic.copy_string(".."));
    visitor :: (info: *File_Utilities.File_Visit_Info, entries: *Entries) {
        if OS == .LINUX && info.short_name[0] == #char "." then return;
        if OS == .WINDOWS && info.short_name[0] == #char "$" then return;

        if info.is_directory then Basic.array_add(*entries.directories, Basic.copy_string(info.short_name));
        else if String.ends_with(info.short_name, instance.fileSelect.extensionFilter) {
            Basic.array_add(*entries.files, Basic.copy_string(info.short_name));
        }
    }
    File_Utilities.visit_files(path, false, *entries, visitor, visit_directories = true, follow_symlinks = false);

    Sort.quick_sort(entries.directories, String.compare_nocase);
    Sort.quick_sort(entries.files, String.compare_nocase);
    for directoryName : entries.directories {
        entryEntity := _make_entry(directoryName, true);
    }
    for fileName : entries.files {
        entryEntity := _make_entry(fileName, false);
    }
}

_make_entry :: (name : string, isDirectory : bool) -> *EntryEntity {
    entryEntity := SillMeta.create_entry_entity(instance.engine);
    entryEntity.isDirectory = isDirectory;
    entryEntity.fileOrDirectoryName = name;
    entryEntity.name = name;
    entryEntity.ui.anchor = .TopLeft;
    Sill.entity_add_child(instance.fileSelect, entryEntity);

    // Text mesh
    textMesh := create_text_mesh();
    Basic.array_add(*entryEntity.mesh.nodes, .{});
    Basic.array_add(*entryEntity.mesh.nodes[0].primitives, textMesh);
    charInfos := text_mesh_update(textMesh, Basic.tprint("% %", (ifx isDirectory then ForkAwesome.Folder else ForkAwesome.FileO), name),
                                  *instance.fonts.light, *instance.config.env.textColor);
    Basic.array_free(charInfos);
    entryEntity.ui.extent.width = 400;
    entryEntity.ui.extent.height = UiConstants.HeightLine;

    // Selection rectangle
    squareMesh := create_rect_mesh(); // @todo Anchor in create_rect_mesh?
    squareMesh.vertices[0].position = .{0, 0, 5};
    squareMesh.vertices[1].position = .{0, UiConstants.HeightLine - 4, 5}; // @todo Complete heuristic about the rendering...
    squareMesh.vertices[2].position = .{400, UiConstants.HeightLine - 4, 5};
    squareMesh.vertices[3].position = .{400, 0, 5};
    squareMesh.material = Magma.create_material(instance.shaders.monochrome);
    squareMesh.disabled = true;
    Magma.material_set(squareMesh.material, "color", instance.config.env.selectionBackgroundColor);
    Basic.array_add(*entryEntity.mesh.nodes[0].primitives, squareMesh);

    Sill.ui_on_trigger(*entryEntity.ui, (trigger : Sill.UiTrigger, entryEntity : *EntryEntity) {
        if trigger.flags & .Hover {
            <<trigger.stopPropagation = true; // @fixme Does that make sense?
            entryEntity.mesh.nodes[0].primitives[1].disabled = false;
            Crater.window_pointer_style(instance.engine.window, .HandPointer);
        } else if trigger.flags & .NoHover {
            entryEntity.mesh.nodes[0].primitives[1].disabled = true;
            Crater.window_pointer_style(instance.engine.window, .Default);
        } else if trigger.flags & .Click {
            if !instance.fileSelect then return;
            if entryEntity.isDirectory {
                _go_into_directory(entryEntity.fileOrDirectoryName);
            } else if String.ends_with(entryEntity.fileOrDirectoryName, ".pgn") {
                instance.fileSelect.callback(Basic.tprint("%/%", instance.fileSelect.currentPath, entryEntity.fileOrDirectoryName));
                Sill.destroy_entity(instance.fileSelect, destroyChildren = true);
                instance.fileSelect = null;
            }
        }
    }, Sill.UiCallbackFlags.Hover | .NoHover | .Click, entryEntity);

    return entryEntity;
}

_place_children :: (fileSelect : *FileSelectEntity) {
    currentPosition : Chamber.vec2; // Relative to the fileSelect, therefore starting at (0,0).
    currentPosition.y += UiConstants.HeightLine;
    for child : fileSelect.children {
        entryEntity := cast(*EntryEntity) child;
        entryEntity.transform.translation.xy = currentPosition;
        Sill.transform_commit(*entryEntity.transform);
        currentPosition.y += entryEntity.ui.extent.height;
    }
}

File_Utilities :: #import "File_Utilities";
Sort :: #import "Sort";
String :: #import "String";
