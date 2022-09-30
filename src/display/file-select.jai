FileSelectEntity :: struct {
    using #as entity : Sill.Entity;

    ui : Sill.UiComponent;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    listener : Sill.ListenerComponent;

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
    using #as entity : Sill.Entity;

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
    Sill.listener_on_message(*fileSelect.listener, _on_message);
    fileSelect.extensionFilter = extensionFilter;
    fileSelect.callback = callback;

    mesh := create_text_mesh();
    Basic.array_add(*fileSelect.mesh.nodes, .{});
    Basic.array_add(*fileSelect.mesh.nodes[0].primitives, mesh);

    charInfos := text_mesh_update(mesh, Basic.tprint("Select a % file", extensionFilter), "mainBold", *instance.config.env.textColor);
    Basic.array_free(charInfos);

    Sill.ui_on_trigger(*fileSelect.ui, (trigger : Sill.UiTrigger, fileSelect : *FileSelectEntity) {
        _place_children(fileSelect);
    }, .Child, fileSelect);

    path : string;
    if instance.persistence.fileSelect.lastPath.count != 0 {
        path = Basic.copy_string(instance.persistence.fileSelect.lastPath);
    } else {
        path = Chamber.os_user_path();
    }
    _show_path(fileSelect, path);

    _reflow(fileSelect);
}

#scope_file

_on_message :: (using fileSelect : *FileSelectEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _reflow(fileSelect);
    }
}

_reflow :: (fileSelect : *FileSelectEntity) {
    extent := Crater.window_get_extent(instance.engine.window);

    fileSelect.transform.translation.x = UiConstants.PaddingHorizontal;
    fileSelect.transform.translation.y = - cast(s32) extent.height / 2 + UiConstants.PaddingVertical;
    fileSelect.ui.extent.width = extent.width - 2 * UiConstants.PaddingHorizontal;
    fileSelect.ui.extent.height = extent.height - 2 * UiConstants.PaddingVertical;
    fileSelect.ui.anchor = .TopLeft;

    Sill.transform_commit(*fileSelect.transform);
}

_go_into_directory :: (using fileSelect : *FileSelectEntity, directoryName : string) {
    _show_path(fileSelect, Basic.sprint("%/%", currentPath, directoryName));
}

_show_path :: (using fileSelect : *FileSelectEntity, path : string) {
    // Removing old entries...
    for child : children {
        Sill.destroy_entity(child, warnParent = false);
    }
    children.count = 0;

    Basic.free(currentPath);
    currentPath = path;

    Data :: struct {
        fileSelect : *FileSelectEntity;
        entries : Entries;
    };
    data : Data;
    data.fileSelect = fileSelect;

    defer { Basic.array_free(data.entries.files); Basic.array_free(data.entries.directories); }
    Basic.array_add(*data.entries.directories, Basic.copy_string(".."));
    visitor :: (info : *File_Utilities.File_Visit_Info, data : *Data) {
        if OS == .LINUX && info.short_name[0] == #char "." then return;
        if OS == .WINDOWS && info.short_name[0] == #char "$" then return;

        if info.is_directory then Basic.array_add(*data.entries.directories, Basic.copy_string(info.short_name));
        else if String.ends_with(info.short_name, data.fileSelect.extensionFilter) {
            Basic.array_add(*data.entries.files, Basic.copy_string(info.short_name));
        }
    }
    File_Utilities.visit_files(path, false, *data, visitor, visit_directories = true, follow_symlinks = false);

    Sort.quick_sort(data.entries.directories, String.compare_nocase);
    Sort.quick_sort(data.entries.files, String.compare_nocase);
    for directoryName : data.entries.directories {
        entryEntity := _make_entry(fileSelect, directoryName, true);
    }
    for fileName : data.entries.files {
        entryEntity := _make_entry(fileSelect, fileName, false);
    }
}

_make_entry :: (fileSelect : *FileSelectEntity, name : string, isDirectory : bool) -> *EntryEntity {
    entryEntity := SillMeta.create_entry_entity(instance.engine);
    entryEntity.isDirectory = isDirectory;
    entryEntity.fileOrDirectoryName = name;
    entryEntity.name = name;
    entryEntity.ui.anchor = .TopLeft;
    Sill.entity_add_child(fileSelect, entryEntity);

    // Text mesh
    textMesh := create_text_mesh();
    Basic.array_add(*entryEntity.mesh.nodes, .{});
    Basic.array_add(*entryEntity.mesh.nodes[0].primitives, textMesh);
    charInfos := text_mesh_update(textMesh, Basic.tprint("% %", (ifx isDirectory then ForkAwesome.Folder else ForkAwesome.FileO), name),
                                  "mainLight", *instance.config.env.textColor);
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
    squareMesh.disabled |= .Application;
    Magma.material_set(squareMesh.material, "color", instance.config.env.selectionBackgroundColor);
    Basic.array_add(*entryEntity.mesh.nodes[0].primitives, squareMesh);

    Sill.ui_on_trigger(*entryEntity.ui, (trigger : Sill.UiTrigger, entryEntity : *EntryEntity) {
        if entryEntity.mesh.nodes.count == 0 then return; // Can happen if the entity is destroyed.

        if trigger.flags & .HoverStart {
            entryEntity.mesh.nodes[0].primitives[1].disabled &= ~.Application;
            Crater.window_pointer_style(instance.engine.window, .HandPointing);
        } else if trigger.flags & .HoverStop {
            entryEntity.mesh.nodes[0].primitives[1].disabled |= .Application;
            Crater.window_pointer_style(instance.engine.window, .Default);
        } else if trigger.flags & .ClickStop {
            fileSelect := cast(*FileSelectEntity) entryEntity.parent;
            if !fileSelect then return;
            if entryEntity.isDirectory {
                _go_into_directory(fileSelect, entryEntity.fileOrDirectoryName);
            } else if String.ends_with(entryEntity.fileOrDirectoryName, ".pgn") {
                if instance.persistence.fileSelect.lastPath.count != 0 {
                    Basic.free(instance.persistence.fileSelect.lastPath);
                }
                instance.persistence.fileSelect.lastPath = Basic.copy_string(fileSelect.currentPath);
                persistence_commit();

                fileSelect.callback(Basic.tprint("%/%", fileSelect.currentPath, entryEntity.fileOrDirectoryName));
                Sill.destroy_entity(fileSelect, destroyChildren = true);
            }
        }
    }, Sill.UiCallbackFlags.HoverStart | .HoverStop | .ClickStop, entryEntity);

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
