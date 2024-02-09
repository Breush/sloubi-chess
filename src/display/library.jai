/*
 * The library is a collection of studies.
 * It's our entry-point in the application, loading or creating games.
 */

LibraryEntity :: struct {
    using #as entity : Sill.Entity;

    ui : Sill.UiComponent;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
    listener : Sill.ListenerComponent;
    tab : TabComponent;

    // Current page displayed
    arianeThread : TransformEntity;
    entries : [..]*EntryEntity;
    rootPath : string;

    currentPath : string;
    inExplorer : bool;

    on_cleanup :: (using this : *LibraryEntity) {
        Basic.free(rootPath);
        Basic.free(currentPath);
        Basic.array_free(entries);
    }
}

EntryEntity :: struct {
    using #as entity : Sill.Entity;

    ui : Sill.UiComponent;
    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;

    text : string;
    callback : #type (this : *EntryEntity);

    data : Data;

    Data :: struct {
        kind : Kind;
        name : string;
        path : string;
        gameIndex : u32;            // When kind == .Game, index of the game in its study.
        games : [..]*EntryEntity;   // When kind == .Study, games within a study.
        folded : bool;              // When kind == .Study, whether the study is folded or not.
    }

    // @note The order of this enum is used to sort entries.
    Kind :: enum u8 {
        Ariane;     // Used in ariane thread.
        Folder;     // Usually a folder (containing studies in library).
        Study;      // Usually a PGN file.
        Game;       // Usually a part of a PGN file.
    }

    on_cleanup :: (using this : *EntryEntity) {
        Basic.free(data.name);
        Basic.free(data.path);
        Basic.array_free(data.games);
    }
}

library_create :: () -> *LibraryEntity {
    library := SillMeta.create_library_entity(instance.engine);

    storagePath := Chamber.os_application_data_storage_path(Basic.temp);
    appStoragePath := Basic.tprint("%.sloubi-chess", storagePath);
    library.rootPath = Basic.sprint(instance.config.library.path, appStoragePath);
    String.path_overwrite_separators(library.rootPath);

    library.tab.text = "Library";
    library.tab.icon = ForkAwesome.Bookmark;
    library.tab.onReflow = xx _on_reflow;
    Basic.array_add(*library.tab.actions, .{ "Import PGNs in library", ForkAwesome.Download, xx _on_import_pgn_in_library, .Right });
    Basic.array_add(*library.tab.actions, .{ "Open PGN from filesystem", ForkAwesome.FolderOpen, xx _on_open_pgn_from_filesystem, .Right });
    Basic.array_add(*library.tab.actions, .{ "Show library", ForkAwesome.Bookmark, xx _on_show_library, .Right });
    Basic.array_add(*library.tab.actions, .{ "Create new study", ForkAwesome.PlusSquare, xx _on_create_new_study, .Left });
    tab_commit_text(*library.tab);

    Sill.entity_set_parent(*library.arianeThread, library);

    _set_current_path(library, library.rootPath);

    send(.SelectTab, library);
    return library;
}

#scope_file

_on_reflow :: (using library : *LibraryEntity) {
    ui.extent.width = tab.page.content.ui.extent.width - 2 * UiConstants.PaddingHorizontal;
}

_reload_from_disk :: (using library : *LibraryEntity) {
    path := library.currentPath;

    tab.actions[0].place = ifx inExplorer then TabComponent.Action.Place.None else .Right;
    tab.actions[1].place = ifx inExplorer then TabComponent.Action.Place.None else .Right;
    tab.actions[2].place = ifx inExplorer then TabComponent.Action.Place.Right else .None;

    _cleanup_entries(library);

    // Add special .. entry.
    if arianeThread.children.count > 1 then {
        backEntry := SillMeta.create_entry_entity(instance.engine);
        backEntry.data.kind = .Folder;
        backEntry.data.name = Basic.copy_string("..");
        backEntry.data.path = Basic.copy_string(String.path_strip_filename(library.currentPath));
        Basic.array_add(*library.entries, backEntry);
    }

    // Add all files.
    visitor :: (info : *FileUtilities.File_Visit_Info, library : *LibraryEntity) {
        if OS == .LINUX && info.short_name[0] == #char "." then return;
        if OS == .WINDOWS && info.short_name[0] == #char "$" then return;

        if info.is_directory || String.ends_with(info.short_name, ".pgn") {
            entry := SillMeta.create_entry_entity(instance.engine);

            entry.data.kind = ifx info.is_directory then EntryEntity.Kind.Folder else .Study;
            entry.data.name = Basic.copy_string(info.short_name);
            entry.data.path = Basic.copy_string(info.full_name);

            if entry.data.kind == .Study {
                study := load_study(entry.data.path, .Info);
                if study == null then return; // Error, not a PGN.
                if study.infoFlags & .MultipleGames == 0 {
                    entry.data.kind = .Game;
                    entry.data.gameIndex = 0;
                }
            }

            Basic.array_add(*library.entries, entry);
        }
    }

    Basic.log("Loading library from '%'", library.currentPath, flags = .VERBOSE_ONLY);
    FileUtilities.visit_files(library.currentPath, false, library, visitor, visit_directories = true, follow_symlinks = false);

    // Sort entries, showing folders-like first, and alphabetic sorting.
    Sort.quick_sort(entries, (a : *EntryEntity, b : *EntryEntity) -> s64 {
        if a.data.kind != b.data.kind then return cast(s64) a.data.kind - cast(s64) b.data.kind;
        return Sort.compare_strings(a.data.name, b.data.name);
    });

    // Refresh entries.
    for entry, entryIndex : library.entries {
        _refresh_entry(library, entry);
    }

    tab_commit_actions(*tab);
}

_refresh_entry :: (using library : *LibraryEntity, entry : *EntryEntity) {
    if entry.callback == null {
        if entry.data.kind == .Folder {
            _make_entry(library, entry.data.name, ForkAwesome.FolderO, entry = entry);
            entry.callback = (using entry : *EntryEntity) {
                library := cast(*LibraryEntity) entry.parent;
                _set_current_path(library, entry.data.path);
            };
        } else if entry.data.kind == .Study {
            _make_entry(library, entry.data.name, ForkAwesome.ChevronCircleRight, entry = entry);
            entry.callback = (using entry : *EntryEntity) {
                entry.data.folded = !entry.data.folded;

                // Create game entries if they didn't exist yet.
                library := cast(*LibraryEntity) entry.parent;
                if entry.data.games.count == 0 {
                    study := load_study(entry.data.path, .GamesTitles);
                    MAX_GAME_COUNT :: 9;
                    for *game, gameIndex : study.games {
                        if study.games.count > MAX_GAME_COUNT && gameIndex > MAX_GAME_COUNT - 2 then break;
                        gameEntry := SillMeta.create_entry_entity(instance.engine);
                        gameEntry.data.kind = .Game;
                        gameEntry.data.name = Basic.copy_string(game.title);
                        gameEntry.data.path = Basic.copy_string(entry.data.path);
                        gameEntry.data.gameIndex = cast(u32) gameIndex;
                        Basic.array_add(*entry.data.games, gameEntry);
                    }
                    if study.games.count > MAX_GAME_COUNT {
                        gameEntry := SillMeta.create_entry_entity(instance.engine);
                        gameEntry.data.kind = .Game;
                        gameEntry.data.name = Basic.sprint("And % more...", study.games.count - MAX_GAME_COUNT + 1);
                        gameEntry.data.path = Basic.copy_string(entry.data.path);
                        gameEntry.data.gameIndex = MAX_GAME_COUNT - 1;
                        Basic.array_add(*entry.data.games, gameEntry);
                    }
                    _refresh_entry(library, entry);
                } else {
                    for game : entry.data.games {
                        Sill.entity_set_disabled(game, entry.data.folded);
                    }
                }

                _place_entries(library);
                _make_entry_name(entry, entry.data.name, ifx entry.data.folded then ForkAwesome.ChevronCircleRight else ForkAwesome.ChevronCircleDown);
            };
        } else if entry.data.kind == .Game {
            _make_entry(library, entry.data.name, ForkAwesome.Gamepad, entry = entry);
            entry.callback = (using entry : *EntryEntity) {
                study := load_study(data.path, .GamesBytes);
                study_show_game(study, data.gameIndex);
            };
        }
    }

    for gameEntry : entry.data.games {
        _refresh_entry(library, gameEntry);
    }

    _place_entries(library);
}

_cleanup_entries :: (using library : *LibraryEntity) {
    for entry, entryIndex : library.entries {
        for gameEntry : entry.data.games {
            Sill.destroy_entity(gameEntry);
        }
        Sill.destroy_entity(entry);
    }
    library.entries.count = 0;
}

_make_entry_name :: (entry : *EntryEntity, text : string, icon : string) -> float {
    textMesh := entry.mesh.nodes[0].primitives[0];
    width := text_mesh_update(textMesh, Basic.tprint(ifx icon.count == 0 then "%1%2" else "% %", icon, text),
                              "mainLight", *instance.config.env.textColor);
    return width;
}

_make_entry :: (parent : *Sill.Entity, text : string, icon : string, fitWidth := false, entry : *EntryEntity = null) -> *EntryEntity {
    if entry == null {
        entry = SillMeta.create_entry_entity(instance.engine);
    } else {
        SillMeta.entity_init(entry, instance.engine);
    }

    entry.text = text;
    entry.ui.anchor = .TopLeft;
    entry.data.folded = true;
    Sill.entity_add_child(parent, entry);

    // Text mesh
    textMesh := create_text_mesh();
    Basic.array_add(*entry.mesh.nodes, .{});
    Basic.array_add(*entry.mesh.nodes[0].primitives, textMesh);
    width := _make_entry_name(entry, text, icon);
    entry.ui.extent.width = ifx fitWidth then width else 400; // @todo Hardcorded
    entry.ui.extent.height = UiConstants.HeightLine;

    // @todo Remove the selection mesh from inside the entry, have only one at Library level...
    // @todo Complete heuristic about the rendering, improve that...
    squareMesh := create_rect_mesh(400, UiConstants.HeightLine - 4, 5, .TopLeft);
    if fitWidth {
        squareMesh.vertices[2].position.x = width + UiConstants.PaddingHorizontalSmall;
        squareMesh.vertices[3].position.x = width + UiConstants.PaddingHorizontalSmall;
    }
    squareMesh.material = Magma.create_material(instance.shaders.gradient);
    squareMesh.disabled |= .Application;
    Magma.material_set_color(squareMesh.material, "color", instance.config.env.hoverColor);
    Magma.material_set_color(squareMesh.material, "fadeColor", instance.config.env.backgroundColor);
    if fitWidth {
        Magma.material_set(squareMesh.material, "fadeInX", 0.2);
        Magma.material_set(squareMesh.material, "fadeOutX", 0.9);
    } else {
        Magma.material_set(squareMesh.material, "fadeInX", 0.07);
        Magma.material_set(squareMesh.material, "fadeOutX", 0.5);
    }
    Basic.array_add(*entry.mesh.nodes[0].primitives, squareMesh);

    Sill.ui_on_trigger(*entry.ui, (trigger : Sill.UiTrigger, entry : *EntryEntity) {
        if entry.mesh.nodes.count == 0 then return; // Can happen if the entity is destroyed.

        if trigger.flags & .HoverStart {
            trigger.stopPropagation.* = true;
            entry.mesh.nodes[0].primitives[1].disabled &= ~.Application;
            Crater.window_pointer_style(instance.engine.window, .HandPointing);

            if entry.data.kind == .Game {
                game := load_game(entry.data.path, entry.data.gameIndex, .Summary);
                board_view_preview_summary(*instance.metaBoard.boardView, game);
            }
        } else if trigger.flags & .HoverStop {
            entry.mesh.nodes[0].primitives[1].disabled |= .Application;
            Crater.window_pointer_style(instance.engine.window, .Default);
        } else if trigger.flags & .ClickStop {
            trigger.stopPropagation.* = true;
            if entry.callback != null then entry.callback(entry);
        }
    }, Sill.UiCallbackFlags.HoverStart | .HoverStop | .ClickStop, entry);

    return entry;
}

_ariane_thread_add :: (using arianeThread : *TransformEntity, data : EntryEntity.Data, icon := ForkAwesome.ChevronRight) {
    arianeEntry := _make_entry(arianeThread, data.name, icon, fitWidth = true);
    arianeEntry.data = data;
    arianeEntry.callback = (using arianeEntry : *EntryEntity) {
        arianeThread := cast(*TransformEntity) arianeEntry.parent;
        if Basic.peek(arianeThread.children) == arianeEntry then return;

        for arianeChild, arianeChildIndex : arianeThread.children {
            if arianeChild == arianeEntry {
                for < i : arianeThread.children.count - 1 .. arianeChildIndex + 1 {
                    Sill.destroy_entity(arianeThread.children[i], warnParent = false);
                }
                arianeThread.children.count = arianeChildIndex + 1;
                break;
            }
        }

        library := cast(*LibraryEntity) arianeThread.parent;
        _set_current_path(library, arianeEntry.data.path);
    };

    library := cast(*LibraryEntity) arianeThread.parent;
    _place_ariane_thread(library);
}

_place_entries :: (using library : *LibraryEntity) {
    currentPosition : Chamber.vec2; // Relative to the library, therefore starting at (0,0).
    currentPosition.y += UiConstants.PaddingVerticalMedium + UiConstants.HeightLine;

    for entry, entryIndex : entries {
        if entry.flags & .Disabled then continue;

        entry.transform.translation.xy = currentPosition;
        currentPosition.y += entry.ui.extent.height;
        Sill.transform_commit(*entry.transform);

        if !entry.data.folded {
            for gameEntry : entry.data.games {
                gameEntry.transform.translation.xy = currentPosition;
                gameEntry.transform.translation.x += UiConstants.PaddingHorizontalMedium;
                currentPosition.y += gameEntry.ui.extent.height;
                Sill.transform_commit(*gameEntry.transform);
            }
        }
    }

    ui.extent.height = currentPosition.y;
}

_place_ariane_thread :: (using library : *LibraryEntity) {
    currentPosition : Chamber.vec2;
    for child : arianeThread.children {
        entry := cast(*EntryEntity) child;
        entry.transform.translation.xy = currentPosition;
        Sill.transform_commit(*entry.transform);
        currentPosition.x += entry.ui.extent.width + UiConstants.PaddingHorizontalSmall;
    }

    _place_entries(library);
}

_set_current_path :: (using library : *LibraryEntity, path : string) {
    Basic.free(library.currentPath);
    library.currentPath = Basic.copy_string(path);
    _refresh_ariane_thread(library);
    _reload_from_disk(library);
}

_refresh_ariane_thread :: (using library : *LibraryEntity) {
    for child : arianeThread.children {
        Sill.destroy_entity(child, warnParent = false);
    }
    arianeThread.children.count = 0;

    // @fixme :JaiBug parse_path does not correctly set the temporary allocator,
    //        so we have to do it manually. (It is overwritten in reduce_path.)
    oldAllocator := context.allocator;
    context.allocator = Basic.temp;

    wordCountToSkip := 0;
    if !inExplorer {
        wordCountToSkip = FileUtilities.parse_path(library.rootPath).words.count;
    }

    splitPath := FileUtilities.parse_path(library.currentPath);
    pathData : EntryEntity.Data;
    pathData.kind = .Ariane;

    context.allocator = oldAllocator;

    if !inExplorer {
        pathData.name = Basic.copy_string("Library");
        pathData.path = Basic.copy_string(library.rootPath);
        _ariane_thread_add(*library.arianeThread, pathData, ForkAwesome.Bookmark);
    } else if splitPath.header_string.count != 0 || splitPath.number_of_leading_slashes > 0 {
        leadingSlashes := ifx splitPath.number_of_leading_slashes > 0 then "/" else "";
        pathData.name = Basic.sprint("%1%2", splitPath.header_string, leadingSlashes);
        pathData.path = FileUtilities.path_to_string(splitPath, 0);
        _ariane_thread_add(*library.arianeThread, pathData, "");
    }
    for word, wordIndex : splitPath.words {
        if wordIndex < wordCountToSkip then continue;
        pathData.name = Basic.copy_string(word);
        pathData.path = FileUtilities.path_to_string(splitPath, wordIndex + 1);
        _ariane_thread_add(*library.arianeThread, pathData, ifx wordIndex != 0 then "/" else "");
    }
}

_on_create_new_study :: (using library : *LibraryEntity) {
    unsavedId : u32;
    filename : string;

    // @todo Would be better to just ask for name on save...
    while true {
        filename = Basic.tprint("%/unsaved-%.pgn", library.currentPath, unsavedId);
        if Hash.table_find_pointer(*instance.studies, filename) == null && !FileUtilities.file_exists(filename) then break;
        unsavedId += 1;
    }

    study := study_find_or_add(filename);
    study_add_game(study);
}

_on_open_pgn_from_filesystem :: (using library : *LibraryEntity) {
    path : string;
    if instance.persistence.fileSelect.lastPath.count != 0 {
        path = instance.persistence.fileSelect.lastPath;
    } else {
        path = Chamber.os_user_path(Basic.temp);
    }

    library.inExplorer = true;
    _set_current_path(library, path);
}

_on_show_library :: (using library : *LibraryEntity) {
    library.inExplorer = false;
    _set_current_path(library, library.rootPath);
}

_on_import_pgn_in_library :: (using library : *LibraryEntity) {
    // @todo Import the TWIC, based on config for the dates.
    dialogData : DialogData(LibraryEntity);
    dialogData.mainText = "Import PGNs in library.";
    dialogData.text = "Do you want to import the demo PGNs automatically, or your own manually?";
    dialogData.choices = .["Demo", "Manually", "Cancel"];
    dialogData.cancelChoiceIndex = 2;
    dialogData.callback = (dialog : *DialogEntity, choiceIndex : u32, library : *LibraryEntity) {
        dialog_close(dialog);

        if choiceIndex == 1 {
            Chamber.os_open_file_explorer(library.rootPath);
        } else if choiceIndex == 0 {
            srcDir := String.join(".", "assets", "demo", "library", separator = Chamber.PATH_SEPARATOR,, Basic.temp);
            Chamber.copy_files_recursively(srcDir, library.currentPath);
            _reload_from_disk(library);
        }
    };
    dialogData.userData = library;
    dialog_create(dialogData);
}

_download_twic_database :: () {
    operator- :: Basic.operator-;
    operator/ :: Basic.operator/;

    firstIssueIndex := 920;
    firstIssueTime := Basic.to_seconds(Basic.calendar_to_apollo(.{year = 2012, month_starting_at_0 = 5, day_of_month_starting_at_0 = 24}));
    issueDelay := 7 * 24 * 60 * 60;

    // ---- Download all 2022 issues.

    // Adjust to the first issue after this date.
    startTime := Basic.to_seconds(Basic.calendar_to_apollo(.{year = 2022, month_starting_at_0 = 0, day_of_month_starting_at_0 = 0}));
    startIssueOffset := (startTime - firstIssueTime) % issueDelay;
    if startIssueOffset != 0 then startTime += issueDelay - startIssueOffset;
    startIssueIndex := firstIssueIndex + (startTime - firstIssueTime) / issueDelay;

    endTime := Basic.to_seconds(Basic.calendar_to_apollo(.{year = 2022, month_starting_at_0 = 11, day_of_month_starting_at_0 = 30}));
    endIssueOffset := (endTime - firstIssueTime) % issueDelay;
    endIssueIndex := firstIssueIndex + (endTime - firstIssueTime) / issueDelay;

    // Do download.
    storagePath := Chamber.os_application_data_storage_path();
    File.os_make_directory_if_it_does_not_exist(Basic.tprint("%.sloubi-chess/downloads/twic/", storagePath));

    // @todo Allow for parallel download, and in another thread, with progress feedback.
    for issueIndex : startIssueIndex .. endIssueIndex {
        sourcePath := Basic.tprint("https://theweekinchess.com/zips/twic%g.zip", issueIndex);
        targetPath := Basic.tprint("%.sloubi-chess/downloads/twic/%.zip", storagePath, issueIndex);

        if FileUtilities.file_exists(targetPath) then continue;

        Chamber.download(sourcePath, targetPath);
    }

    // @todo Missing unzipping...
}
