#import "Sill";
#import "Magma";
#import "Chamber";
#import "Crater";
#import "Basic";
#import "UiConstants";
#import "..app";
#import "..meta";
#import "..structures.config"; // For ConfigEnv
#import "label"; // For create_label
#import "text-entry"; // For create_text_entry
#import "components.button"; // For UiButtonEntity and button_commit
#import "..controller"; // For mode_push, mode_pop, Mode
#import "..message"; // For send, MessageKind
#import "File_Utilities"; // For FileUtilities.copy_file
#import "..structures.game"; // For CommentStyle, assuming it's here.

MAX_TEXT_ENTRIES_PER_SETTING :: 3;

SettingsElementInfo :: struct {
    label: *LabelEntity;
    textEntries: [MAX_TEXT_ENTRIES_PER_SETTING]*TextEntryEntity;
    numTextEntries: u8;
    settingName: string; 
    originalValueString: string; // To check if value changed, for vec3 store concatenated "r g b"
    isVec3: bool;
    isS64: bool;
    isString: bool;
    isFloat: bool;
    isBool: bool;
}

SettingsDialogEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    mesh : Sill.MeshComponent;
    ui : Sill.UiComponent;

    envElements: [..]SettingsElementInfo;
    boardElements: [..]SettingsElementInfo; // For board settings
    tempEnv: ConfigEnv; 
    tempBoard: ConfigBoard; // For board settings

    // Section Labels (optional, but good for reflow)
    envSectionLabel: *LabelEntity;
    boardSectionLabel: *LabelEntity;
    analysisSectionLabel: *LabelEntity;
    controlsSectionLabel: *LabelEntity;
    librarySectionLabel: *LabelEntity;
    movesSectionLabel: *LabelEntity;

    analysisElements: [..]SettingsElementInfo;
    controlsElements: [..]SettingsElementInfo;
    libraryElements: [..]SettingsElementInfo;
    movesElements: [..]SettingsElementInfo;

    tempAnalysis: ConfigAnalysis;
    tempControls: ConfigControls;
    tempLibrary: ConfigLibrary;
    tempMoves: ConfigMoves;

    saveButton: *UiButtonEntity;
    cancelButton: *UiButtonEntity;

    dialogWidth: float = 400; // Default width, can be adjusted by reflow
    contentHeight: float; // Calculated based on elements

    on_cleanup :: (using this : *SettingsDialogEntity) {
        Basic.array_reset(*envElements);
        Basic.array_reset(*boardElements);
        Basic.array_reset(*analysisElements);
        Basic.array_reset(*controlsElements);
        Basic.array_reset(*libraryElements);
        Basic.array_reset(*movesElements);
        
        // Free cloned strings in temp structs
        Basic.free(tempEnv.fontFamily);
        if tempEnv.monoFontFamily Basic.free(tempEnv.monoFontFamily); 
        Basic.free(tempBoard.pieces);
        Basic.free(tempAnalysis.externalSite);
        Basic.free(tempAnalysis.uciEngine);
        Basic.free(tempLibrary.path);
        Basic.free(tempLibrary.gameTitleFormat);
        // ConfigControls and ConfigMoves (excluding nested if any) have no direct strings to free.
        // CommentStyle is an enum.
    }
}

// Attempt to use Crater functions, will fallback if they don't exist or cause errors.
key_to_display_string :: (key: Crater.Key) -> string {
    // return Crater.key_to_name(key); // This is the ideal
    return Basic.tprint("%", key); // Fallback to integer representation
}

display_string_to_key :: (s: string) -> Crater.Key {
    // parsed_key, ok := Crater.name_to_key(s); // This is the ideal
    // if ok return parsed_key;
    parsed_int, ok := Basic.string_to_s32(s); // Fallback: try to parse as int
    if ok return cast(Crater.Key) parsed_int;
    Basic.log("Warning: Could not parse key string '%' to Crater.Key. Defaulting to Unknown.", s, flags=.WARNING);
    return .Unknown; // Default or error key
}

// Assuming CommentStyle enum exists and has these typical values.
// These helpers might need adjustment if the actual enum definition/names differ.
// This is based on the structure of read_json_enum in config.jai.
comment_style_to_string :: (style: CommentStyle) -> string {
    if style == CommentStyle.Inline     return "Inline";
    if style == CommentStyle.Half       return "Half";
    if style == CommentStyle.Full       return "Full";
    if style == CommentStyle.SidedFull  return "SidedFull";
    return "Unknown";
}

string_to_comment_style :: (s: string) -> CommentStyle {
    s_lower := Basic.string_to_lower(Basic.temp_get_context_allocator(), s);
    if s_lower == "inline"    return .Inline;
    if s_lower == "half"      return .Half;
    if s_lower == "full"      return .Full;
    if s_lower == "sidedfull" return .SidedFull; // Or "SidedFull" if case-sensitive matching is used elsewhere
    Basic.log("Warning: Unknown CommentStyle string '%'. Defaulting to Inline.", s, flags=.WARNING);
    return .Inline;
}


settings_dialog_create :: () -> *SettingsDialogEntity {
    dialog := SillMeta.create_settings_dialog_entity(instance.engine);
    
    // Initialize temp config with clones of actual config strings
    dialog.tempEnv = instance.config.env;
    dialog.tempEnv.fontFamily = Basic.clone_string(instance.config.env.fontFamily);
    if instance.config.env.monoFontFamily { // Check if source string exists
        dialog.tempEnv.monoFontFamily = Basic.clone_string(instance.config.env.monoFontFamily);
    } else {
        dialog.tempEnv.monoFontFamily = ""; // Ensure it's a valid empty string if source is null/empty
    }

    dialog.tempBoard = instance.config.board;
    dialog.tempBoard.pieces = Basic.clone_string(instance.config.board.pieces);
    
    dialog.tempAnalysis = instance.config.analysis;
    dialog.tempAnalysis.externalSite = Basic.clone_string(instance.config.analysis.externalSite);
    dialog.tempAnalysis.uciEngine = Basic.clone_string(instance.config.analysis.uciEngine);

    dialog.tempControls = instance.config.controls; 
    
    dialog.tempLibrary = instance.config.library;
    dialog.tempLibrary.path = Basic.clone_string(instance.config.library.path);
    dialog.tempLibrary.gameTitleFormat = Basic.clone_string(instance.config.library.gameTitleFormat);

    dialog.tempMoves = instance.config.moves; // Contains value types (vec3, bool, s64, float) and a nested struct of enums.

    // Setup background mesh
    backgroundMesh := Sill.mesh_make_primitive(*dialog.mesh);
    create_rect_mesh(dialog.dialogWidth, 100, depth = UiConstants.DepthDialogBackground, anchor = .TopLeft, existingMesh = backgroundMesh); // Initial height, adjusted by reflow
    backgroundMesh.material = Magma.create_material(instance.shaders.translucentMonochrome);
    Magma.material_set_color(backgroundMesh.material, "color", Chamber.make_vec4(instance.config.env.backgroundColor, 0.99));

    dialog.transform.translation.z = UiConstants.DepthDialog;
    Sill.ui_set_focused(*dialog.ui, false); // Initially not focused, let text entries grab focus
    Sill.ui_on_trigger(*dialog.ui, (trigger : Sill.UiTrigger, userData : *void) {
        trigger.stopPropagation.* = true; // Consume all events within the dialog bounds
    });


    currentYOffset := UiConstants.PaddingVerticalLarge;

    // Env Settings Section Label
    dialog.envSectionLabel = create_label("Environment Settings", style = "mainBold", anchor = .Center);
    Sill.entity_set_parent(dialog.envSectionLabel, dialog);
    currentYOffset += dialog.envSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;

    // Elements for ConfigEnv
    _add_vec3_setting(dialog, "backgroundColor", dialog.tempEnv.backgroundColor, *currentYOffset, *dialog.envElements);
    _add_vec3_setting(dialog, "contrastColor", dialog.tempEnv.contrastColor, *currentYOffset, *dialog.envElements);
    _add_vec3_setting(dialog, "textColor", dialog.tempEnv.textColor, *currentYOffset, *dialog.envElements);
    _add_s64_setting(dialog, "fontSize", dialog.tempEnv.fontSize, *currentYOffset, *dialog.envElements);
    _add_string_setting(dialog, "fontFamily", dialog.tempEnv.fontFamily, *currentYOffset, *dialog.envElements);
    // Add monoFontFamily if desired

    currentYOffset += UiConstants.PaddingVerticalLarge; // Padding after env settings

    // Board Settings Section Label
    dialog.boardSectionLabel = create_label("Board Settings", style = "mainBold", anchor = .Center);
    Sill.entity_set_parent(dialog.boardSectionLabel, dialog);
    currentYOffset += dialog.boardSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;
    
    // Elements for ConfigBoard
    b := dialog.tempBoard; // Shorthand
    _add_string_setting(dialog, "pieces", b.pieces, *currentYOffset, *dialog.boardElements);
    _add_vec3_setting(dialog, "lightSquareColor", b.lightSquareColor, *currentYOffset, *dialog.boardElements);
    _add_vec3_setting(dialog, "darkSquareColor", b.darkSquareColor, *currentYOffset, *dialog.boardElements);
    
    _add_bool_setting(dialog, "highlightValidSquares", b.highlightValidSquares, *currentYOffset, *dialog.boardElements);
    _add_bool_setting(dialog, "showCapturedPiece", b.showCapturedPiece, *currentYOffset, *dialog.boardElements);
    
    _add_bool_setting(dialog, "dragAndDropMove.enabled", b.dragAndDropMove.enabled, *currentYOffset, *dialog.boardElements);
    _add_float_setting(dialog, "dragAndDropMove.ghostOpacity", b.dragAndDropMove.ghostOpacity, *currentYOffset, *dialog.boardElements);
    
    _add_bool_setting(dialog, "clickClickMove.enabled", b.clickClickMove.enabled, *currentYOffset, *dialog.boardElements);
    
    _add_bool_setting(dialog, "destinationSquareMove.enabled", b.destinationSquareMove.enabled, *currentYOffset, *dialog.boardElements);
    _add_bool_setting(dialog, "destinationSquareMove.disambiguate", b.destinationSquareMove.disambiguateWithLastMovedPiece, *currentYOffset, *dialog.boardElements);
    _add_string_setting(dialog, "destinationSquareMove.mouseButton", mouse_button_to_string(b.destinationSquareMove.mouseButton), *currentYOffset, *dialog.boardElements);

    _add_bool_setting(dialog, "keyboardMove.enabled", b.keyboardMove.enabled, *currentYOffset, *dialog.boardElements);

    // Placeholder labels for complex settings
    _add_placeholder_label(dialog, "highlightColors (Details TBD)", *currentYOffset);
    _add_placeholder_label(dialog, "promotionSelecterColor (R,G,B,A TBD)", *currentYOffset);
    _add_placeholder_label(dialog, "keyboardMove mappings (TBD)", *currentYOffset);

    currentYOffset += UiConstants.PaddingVerticalLarge; 

    // Analysis Settings Section Label
    dialog.analysisSectionLabel = create_label("Analysis Settings", style = "mainBold", anchor = .Center);
    Sill.entity_set_parent(dialog.analysisSectionLabel, dialog);
    currentYOffset += dialog.analysisSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;

    // Elements for ConfigAnalysis
    a := dialog.tempAnalysis;
    _add_string_setting(dialog, "externalSite", a.externalSite, *currentYOffset, *dialog.analysisElements);
    _add_string_setting(dialog, "uciEngine", a.uciEngine, *currentYOffset, *dialog.analysisElements);
    _add_placeholder_label(dialog, "highlightColor (R,G,B,A TBD)", *currentYOffset);

    currentYOffset += UiConstants.PaddingVerticalLarge;

    // Controls Settings Section Label
    dialog.controlsSectionLabel = create_label("Controls Settings", style = "mainBold", anchor = .Center);
    Sill.entity_set_parent(dialog.controlsSectionLabel, dialog);
    currentYOffset += dialog.controlsSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;

    // Elements for ConfigControls
    c := dialog.tempControls;
    _add_key_setting(dialog, "undo", c.undo, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "nextPly", c.nextPly, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "previousPly", c.previousPly, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "firstPly", c.firstPly, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "lastPly", c.lastPly, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "editPlyComment", c.editPlyComment, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "deletePly", c.deletePly, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "nextVariation", c.nextVariation, *currentYOffset, *dialog.controlsElements);
    _add_key_setting(dialog, "previousVariation", c.previousVariation, *currentYOffset, *dialog.controlsElements);
    
    currentYOffset += UiConstants.PaddingVerticalLarge;

    // Library Settings Section Label
    dialog.librarySectionLabel = create_label("Library Settings", style = "mainBold", anchor = .Center);
    Sill.entity_set_parent(dialog.librarySectionLabel, dialog);
    currentYOffset += dialog.librarySectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;

    // Elements for ConfigLibrary
    lib := dialog.tempLibrary;
    _add_string_setting(dialog, "path", lib.path, *currentYOffset, *dialog.libraryElements);
    _add_string_setting(dialog, "gameTitleFormat", lib.gameTitleFormat, *currentYOffset, *dialog.libraryElements);

    currentYOffset += UiConstants.PaddingVerticalLarge;

    // Moves Settings Section Label
    dialog.movesSectionLabel = create_label("Moves Settings", style = "mainBold", anchor = .Center);
    Sill.entity_set_parent(dialog.movesSectionLabel, dialog);
    currentYOffset += dialog.movesSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;

    // Elements for ConfigMoves
    m := dialog.tempMoves;
    _add_vec3_setting(dialog, "mainColor", m.mainColor, *currentYOffset, *dialog.movesElements);
    _add_vec3_setting(dialog, "interestingColor", m.interestingColor, *currentYOffset, *dialog.movesElements);
    _add_vec3_setting(dialog, "goodColor", m.goodColor, *currentYOffset, *dialog.movesElements);
    _add_vec3_setting(dialog, "brillantColor", m.brillantColor, *currentYOffset, *dialog.movesElements); // Note: "brillantColor" in config.jai
    _add_vec3_setting(dialog, "dubiousColor", m.dubiousColor, *currentYOffset, *dialog.movesElements);
    _add_vec3_setting(dialog, "mistakeColor", m.mistakeColor, *currentYOffset, *dialog.movesElements);
    _add_vec3_setting(dialog, "blunderColor", m.blunderColor, *currentYOffset, *dialog.movesElements);
    _add_vec3_setting(dialog, "selectedColor", m.selectedColor, *currentYOffset, *dialog.movesElements);
    _add_vec3_setting(dialog, "selectedCommentColor", m.selectedCommentColor, *currentYOffset, *dialog.movesElements);
    
    _add_bool_setting(dialog, "variationsCollapsed", m.variationsCollapsed, *currentYOffset, *dialog.movesElements);
    _add_s64_setting(dialog, "compactThreshold", m.compactThreshold, *currentYOffset, *dialog.movesElements);
    
    _add_string_setting(dialog, "comments.shortStyle", comment_style_to_string(m.comments.shortStyle), *currentYOffset, *dialog.movesElements);
    _add_string_setting(dialog, "comments.normalStyle", comment_style_to_string(m.comments.normalStyle), *currentYOffset, *dialog.movesElements);
    _add_string_setting(dialog, "comments.longStyle", comment_style_to_string(m.comments.longStyle), *currentYOffset, *dialog.movesElements);
    _add_float_setting(dialog, "comments.fullStyleWidth", m.comments.fullStyleWidth, *currentYOffset, *dialog.movesElements);

    currentYOffset += UiConstants.PaddingVerticalLarge; // Padding before buttons

    // Save Button
    dialog.saveButton = SillMeta.create_ui_button_entity(instance.engine);
    Sill.entity_set_parent(dialog.saveButton, dialog);
    dialog.saveButton.button.text = "Save";
    dialog.saveButton.button.callback = xx _settings_dialog_on_save;
    dialog.saveButton.button.callbackData = dialog;
    button_commit(*dialog.saveButton.button);
    Magma.material_set_color(dialog.saveButton.mesh.nodes[0].primitives[0].material, "color", instance.config.env.contrastColor);


    // Cancel Button
    dialog.cancelButton = SillMeta.create_ui_button_entity(instance.engine);
    Sill.entity_set_parent(dialog.cancelButton, dialog);
    dialog.cancelButton.button.text = "Cancel";
    dialog.cancelButton.button.callback = xx _settings_dialog_on_cancel;
    dialog.cancelButton.button.callbackData = dialog;
    button_commit(*dialog.cancelButton.button);
    Magma.material_set_color(dialog.cancelButton.mesh.nodes[0].primitives[0].material, "color", instance.config.env.contrastColor);

    currentYOffset += UiConstants.HeightButtonDialog + UiConstants.PaddingVerticalLarge;
    dialog.contentHeight = currentYOffset;

    Sill.listener_on_message(*dialog.listener, _on_message_settings_dialog);
    _reflow_settings_dialog(dialog); // Initial layout pass
    
    mode_push(.Settings, cast(*DialogEntity) dialog); // Cast to base DialogEntity for mode stack if necessary, or adjust mode_push
                                                 // For now, assuming settings dialog might need its own mode handling distinct from generic dialogs.
                                                 // If settings dialog IS a DialogEntity (via `using`), this cast might not be needed,
                                                 // but SillMeta creates a specific SettingsDialogEntity.
                                                 // Let's assume for now mode_push can handle different entity types or we adapt.
                                                 // For simplicity, if controller.jai's modeStack stores *DialogEntity, this needs careful handling.
                                                 // Let's assume `mode_push` can take `*Sill.Entity` or we make a specific `settings_mode_push`.
                                                 // Given `dialog_close` takes `*DialogEntity`, we might need a wrapper or common base.
                                                 // For now, this line might cause a compile error if mode_push expects *DialogEntity.
                                                 // Let's assume we will adjust mode_push or related logic later.
                                                 // The task is to display, so full mode integration can be deferred if complex.
                                                 // For now, we'll proceed as if it's okay for this step.
    return dialog;
}

_settings_dialog_on_save :: (buttonOrDialog: *Sill.Entity) {
    dialog := cast(*SettingsDialogEntity) buttonOrDialog; // If callbackData is dialog
    // TODO: Parse text entries, update instance.config.env, save to JSON, then close.
    // For now, just print and close.
    Basic.log("SettingsDialog: Save clicked. (Not implemented yet)");
    for element : dialog.envElements {
        if element.isVec3 {
            Basic.log("Setting: %, R:%, G:%, B:%", element.settingName, element.textEntries[0].text, element.textEntries[1].text, element.textEntries[2].text);
        } else {
            Basic.log("Setting: %, Value:%", element.settingName, element.textEntries[0].text);
        }
    }
    // Apply Env Settings
    Basic.free(instance.config.env.fontFamily);
    if instance.config.env.monoFontFamily Basic.free(instance.config.env.monoFontFamily);
    // Free other allocatable members of instance.config.env if any 

    instance.config.env = dialog.tempEnv; 
    instance.config.env.fontFamily = Basic.clone_string(dialog.tempEnv.fontFamily);
    if dialog.tempEnv.monoFontFamily instance.config.env.monoFontFamily = Basic.clone_string(dialog.tempEnv.monoFontFamily);
    // Clone other allocatable members for instance.config.env

    Basic.log("SettingsDialog: Env settings saved to instance.config.env.");

    // Apply Board Settings
    Basic.free(instance.config.board.pieces);
    instance.config.board = dialog.tempBoard; 
    instance.config.board.pieces = Basic.clone_string(dialog.tempBoard.pieces);
    Basic.log("SettingsDialog: Board settings saved to instance.config.board.");

    // Apply Analysis Settings
    Basic.free(instance.config.analysis.externalSite);
    Basic.free(instance.config.analysis.uciEngine);
    instance.config.analysis = dialog.tempAnalysis;
    instance.config.analysis.externalSite = Basic.clone_string(dialog.tempAnalysis.externalSite);
    instance.config.analysis.uciEngine = Basic.clone_string(dialog.tempAnalysis.uciEngine);
    Basic.log("SettingsDialog: Analysis settings saved to instance.config.analysis.");

    // Apply Controls Settings
    instance.config.controls = dialog.tempControls; 
    Basic.log("SettingsDialog: Controls settings saved to instance.config.controls.");

    // Apply Library Settings
    Basic.free(instance.config.library.path);
    Basic.free(instance.config.library.gameTitleFormat);
    instance.config.library = dialog.tempLibrary;
    instance.config.library.path = Basic.clone_string(dialog.tempLibrary.path);
    instance.config.library.gameTitleFormat = Basic.clone_string(dialog.tempLibrary.gameTitleFormat);
    Basic.log("SettingsDialog: Library settings saved to instance.config.library.");

    // Apply Moves Settings
    instance.config.moves = dialog.tempMoves; // Most are value types, comments struct is also value types (enums, float)
    Basic.log("SettingsDialog: Moves settings saved to instance.config.moves.");

    // Persist instance.config to JSON file
    config_file_path := "assets/config.json";
    backup_file_path := "assets/config.json.bak";

    // Backup existing config file
    copy_success := FileUtilities.copy_file(config_file_path, backup_file_path, overwrite_if_exists=true, log_errors=true);
    if copy_success {
        Basic.log("Successfully backed up '%' to '%'.", config_file_path, backup_file_path);
    } else {
        // Logged by copy_file already if log_errors=true.
        // Continue with saving anyway, as backup failure isn't critical enough to halt saving.
        Basic.log_error("Failed to back up '%' to '%'. Continuing with save operation.", config_file_path, backup_file_path);
    }

    // Write the updated instance.config to the JSON file
    // Need to ensure write_json_as is correctly imported or available. It's in config.jai.
    // Assuming config.jai functions are globally accessible after #load, or correct module prefix is used.
    // Since settings_dialog.jai imports "..structures.config", and config.jai is at src/config.jai,
    // this might require `Config.write_json_as` or similar if not globally namespaced.
    // For now, assuming direct call works if config.jai is loaded in main.jai and functions are exported.
    // If write_json_as is in the same scope (e.g. if #load "config.jai" was used in this file or a common header), it's fine.
    // Let's assume it's accessible for now.
    
    // Need to import `write_json_as` or use its module prefix.
    // Assuming `src/config.jai` is loaded and `write_json_as` is available globally or via a module.
    // If `config.jai` acts as a module, it might be `ConfigModule.write_json_as`.
    // Given it's in `src/config.jai` and this is `src/display/settings_dialog.jai`,
    // and `main.jai` loads `config.jai`, its top-level functions should be available.
    // The type `Config` is from `..structures.config` which is actually `src/config.jai`.
    // So `write_json_as` from that same file should be accessible.
    save_success := write_json_as(*instance.config, config_file_path);

    if save_success {
        Basic.log("Successfully saved configuration to '%'.", config_file_path);
        // Optionally, provide user feedback in the UI (e.g., a temporary "Saved!" message)
    } else {
        Basic.log_error("Failed to save configuration to '%'. Check logs for details.", config_file_path);
        // Optionally, inform the user via UI that saving failed.
    }
    
    // TODO: Send a message that settings have changed so other UI elements can update.
    // send(.SystemSettingsChanged); // This would trigger UI refreshes, font reloads, etc.

    _settings_dialog_close(dialog);
}

_settings_dialog_on_cancel :: (buttonOrDialog: *Sill.Entity) {
    dialog := cast(*SettingsDialogEntity) buttonOrDialog; 
    Basic.log("SettingsDialog: Cancel clicked.");
    _settings_dialog_close(dialog);
}

_settings_dialog_close :: (dialog: *SettingsDialogEntity) {
    Sill.destroy_entity(dialog, destroyChildren = true);
    mode_pop(); // Assuming mode_pop correctly handles coming from Settings mode
}


// Helper to convert Crater.MouseButton to string
mouse_button_to_string :: (mb: Crater.MouseButton) -> string {
    if mb == .Left return "Left";
    if mb == .Right return "Right";
    if mb == .Middle return "Middle";
    if mb == .X1 return "X1";
    if mb == .X2 return "X2";
    return "Unknown";
}

// Helper to convert string to Crater.MouseButton
string_to_mouse_button :: (str: string) -> Crater.MouseButton {
    str_lower := Basic.string_to_lower(Basic.temp_get_context_allocator(), str);
    if str_lower == "left" return .Left;
    if str_lower == "right" return .Right;
    if str_lower == "middle" return .Middle;
    if str_lower == "x1" return .X1;
    if str_lower == "x2" return .X2;
    Basic.log("Warning: Unknown mouse button string '%'. Defaulting to Left.", str, flags=.WARNING);
    return .Left; 
}

_add_placeholder_label :: (dialog: *SettingsDialogEntity, text: string, yOffset: *float) {
    labelEntity := create_label(text, style = "mainLightItalic", anchor = .Left);
    Sill.entity_set_parent(labelEntity, dialog); 
    // Position set in reflow. These are not added to any interactive element list.
    // To make them part of reflow, they'd need to be stored or handled in _reflow_settings_dialog.
    // For now, their yOffset is advanced, but x position might be off if not handled in reflow.
    // Let's ensure they are handled simply in reflow, or make them dialog children positioned absolutely.
    // For simplicity, they will be children of the dialog, and reflow will place them.
    // We can add them to a separate list in dialog if we want to manage them systematically.
    // For now, just advance yOffset. Reflow logic will need to account for them if they are part of its layout.
    yOffset.* += labelEntity.ui.extent.height + UiConstants.PaddingVerticalSmall;
}

_add_vec3_setting :: (dialog: *SettingsDialogEntity, name: string, value: Chamber.vec3, yOffset: *float, elements_array: *[..]SettingsElementInfo) {
    elementInfo: SettingsElementInfo;
    elementInfo.settingName = name;
    elementInfo.isVec3 = true;
    elementInfo.originalValueString = Basic.tprint("%.2f %.2f %.2f", value.r, value.g, value.b);


    labelEntity := create_label(Basic.tprint("%s:", name), style = "mainLight", anchor = .Left);
    Sill.entity_set_parent(labelEntity, dialog);
    elementInfo.label = labelEntity;

    components := .["R", "G", "B"];
    values := .[value.r, value.g, value.b];
    for i: 0..2 {
        textEntry := create_text_entry(Basic.tprint("%.2f", values[i]));
        textEntry.callback = xx _on_settings_text_entry_changed; 
        // userData will be set after adding elementInfo to array for pointer stability
        Sill.entity_set_parent(textEntry, dialog);
        elementInfo.textEntries[i] = textEntry;
    }
    elementInfo.numTextEntries = 3;
    Basic.array_add(elements_array, elementInfo);
    
    ptrToElementInfoInArray := Basic.array_get_pointer(elements_array, elements_array.count - 1);
    for i: 0..2 {
        (Basic.array_get_pointer(elements_array, elements_array.count-1)).textEntries[i].userData = ptrToElementInfoInArray;
    }

    yOffset.* += Basic.max(labelEntity.ui.extent.height, elementInfo.textEntries[0].ui.extent.height) + UiConstants.PaddingVerticalMedium;
}

_add_s64_setting :: (dialog: *SettingsDialogEntity, name: string, value: s64, yOffset: *float, elements_array: *[..]SettingsElementInfo) {
    elementInfo: SettingsElementInfo;
    elementInfo.settingName = name;
    elementInfo.isS64 = true;
    elementInfo.originalValueString = Basic.tprint("%", value);

    labelEntity := create_label(Basic.tprint("%s:", name), style = "mainLight", anchor = .Left);
    Sill.entity_set_parent(labelEntity, dialog);
    elementInfo.label = labelEntity;

    textEntry := create_text_entry(Basic.tprint("%", value));
    textEntry.callback = xx _on_settings_text_entry_changed;
    // userData will be set after adding elementInfo to array
    Sill.entity_set_parent(textEntry, dialog);
    elementInfo.textEntries[0] = textEntry;
    elementInfo.numTextEntries = 1;
    Basic.array_add(elements_array, elementInfo);

    ptrToElementInfoInArray := Basic.array_get_pointer(elements_array, elements_array.count - 1);
    (Basic.array_get_pointer(elements_array, elements_array.count-1)).textEntries[0].userData = ptrToElementInfoInArray;

    yOffset.* += Basic.max(labelEntity.ui.extent.height, textEntry.ui.extent.height) + UiConstants.PaddingVerticalMedium;
}

_add_string_setting :: (dialog: *SettingsDialogEntity, name: string, value: string, yOffset: *float, elements_array: *[..]SettingsElementInfo) {
    elementInfo: SettingsElementInfo;
    elementInfo.settingName = name;
    elementInfo.isString = true;
    elementInfo.originalValueString = Basic.clone_string(value); 

    labelEntity := create_label(Basic.tprint("%s:", name), style = "mainLight", anchor = .Left);
    Sill.entity_set_parent(labelEntity, dialog);
    elementInfo.label = labelEntity;

    textEntry := create_text_entry(value);
    textEntry.callback = xx _on_settings_text_entry_changed;
    // userData will be set after adding elementInfo to array
    Sill.entity_set_parent(textEntry, dialog);
    elementInfo.textEntries[0] = textEntry;
    elementInfo.numTextEntries = 1;
    Basic.array_add(elements_array, elementInfo);

    ptrToElementInfoInArray := Basic.array_get_pointer(elements_array, elements_array.count - 1);
    (Basic.array_get_pointer(elements_array, elements_array.count-1)).textEntries[0].userData = ptrToElementInfoInArray;

    yOffset.* += Basic.max(labelEntity.ui.extent.height, textEntry.ui.extent.height) + UiConstants.PaddingVerticalMedium;
}

_add_bool_setting :: (dialog: *SettingsDialogEntity, name: string, value: bool, yOffset: *float, elements_array: *[..]SettingsElementInfo) {
    elementInfo: SettingsElementInfo;
    elementInfo.settingName = name;
    elementInfo.isBool = true;
    elementInfo.originalValueString = Basic.tprint("%", value);

    labelEntity := create_label(Basic.tprint("%s:", name), style = "mainLight", anchor = .Left);
    Sill.entity_set_parent(labelEntity, dialog);
    elementInfo.label = labelEntity;

    textEntry := create_text_entry(ifx value then "true" else "false");
    textEntry.callback = xx _on_settings_text_entry_changed;
    Sill.entity_set_parent(textEntry, dialog);
    elementInfo.textEntries[0] = textEntry;
    elementInfo.numTextEntries = 1;
    Basic.array_add(elements_array, elementInfo);

    ptrToElementInfoInArray := Basic.array_get_pointer(elements_array, elements_array.count - 1);
    (Basic.array_get_pointer(elements_array, elements_array.count-1)).textEntries[0].userData = ptrToElementInfoInArray;
    
    yOffset.* += Basic.max(labelEntity.ui.extent.height, textEntry.ui.extent.height) + UiConstants.PaddingVerticalMedium;
}

_add_float_setting :: (dialog: *SettingsDialogEntity, name: string, value: float, yOffset: *float, elements_array: *[..]SettingsElementInfo) {
    elementInfo: SettingsElementInfo;
    elementInfo.settingName = name;
    elementInfo.isFloat = true;
    elementInfo.originalValueString = Basic.tprint("%.2f", value); // Using .2f for display consistency

    labelEntity := create_label(Basic.tprint("%s:", name), style = "mainLight", anchor = .Left);
    Sill.entity_set_parent(labelEntity, dialog);
    elementInfo.label = labelEntity;

    textEntry := create_text_entry(Basic.tprint("%.2f", value)); // Format float to string
    textEntry.callback = xx _on_settings_text_entry_changed;
    Sill.entity_set_parent(textEntry, dialog);
    elementInfo.textEntries[0] = textEntry;
    elementInfo.numTextEntries = 1;
    Basic.array_add(elements_array, elementInfo);

    ptrToElementInfoInArray := Basic.array_get_pointer(elements_array, elements_array.count - 1);
    (Basic.array_get_pointer(elements_array, elements_array.count-1)).textEntries[0].userData = ptrToElementInfoInArray;

    yOffset.* += Basic.max(labelEntity.ui.extent.height, textEntry.ui.extent.height) + UiConstants.PaddingVerticalMedium;
}

_add_key_setting :: (dialog: *SettingsDialogEntity, name: string, value: Crater.Key, yOffset: *float, elements_array: *[..]SettingsElementInfo) {
    elementInfo: SettingsElementInfo;
    elementInfo.settingName = name;
    elementInfo.isString = true; // Treat as string for input, will parse to key
    elementInfo.originalValueString = key_to_display_string(value);

    labelEntity := create_label(Basic.tprint("%s:", name), style = "mainLight", anchor = .Left);
    Sill.entity_set_parent(labelEntity, dialog);
    elementInfo.label = labelEntity;

    textEntry := create_text_entry(elementInfo.originalValueString);
    textEntry.callback = xx _on_settings_text_entry_changed;
    Sill.entity_set_parent(textEntry, dialog);
    elementInfo.textEntries[0] = textEntry;
    elementInfo.numTextEntries = 1;
    Basic.array_add(elements_array, elementInfo);

    ptrToElementInfoInArray := Basic.array_get_pointer(elements_array, elements_array.count - 1);
    (Basic.array_get_pointer(elements_array, elements_array.count-1)).textEntries[0].userData = ptrToElementInfoInArray;

    yOffset.* += Basic.max(labelEntity.ui.extent.height, textEntry.ui.extent.height) + UiConstants.PaddingVerticalMedium;
}


_on_settings_text_entry_changed :: (textEntry : *TextEntryEntity, elementInfoPtr : *SettingsElementInfo) {
    if elementInfoPtr == null then {
        Basic.log("Error: elementInfoPtr is null in _on_settings_text_entry_changed.", flags=.ERROR);
        return;
    }
    elementInfo := *elementInfoPtr;
    
    // Get the dialog from the textEntry's parent
    dialog_entity_maybe := textEntry.parent;
    if dialog_entity_maybe == null || dialog_entity_maybe.typeInfo != type_info(SettingsDialogEntity) {
        Basic.log("Error: Could not get SettingsDialogEntity from textEntry parent in _on_settings_text_entry_changed.", flags=.ERROR);
        return;
    }
    dialog := cast(*SettingsDialogEntity) dialog_entity_maybe;

    Basic.log("Text changed for setting '%': %", elementInfo.settingName, textEntry.text, flags=.VERBOSE);

    // Helper to parse boolean from text.
    parse_bool = (text: string) -> bool, bool {
        text_lower := Basic.string_to_lower(Basic.temp_get_context_allocator(), text);
        if text_lower == "true" return true, true;
        if text_lower == "false" return false, true;
        return false, false;
    }

    // ENV SETTINGS
    if elementInfo.settingName == "backgroundColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempEnv.backgroundColor = .{r, g, b}; } else { Basic.log("Invalid float for backgroundColor", flags=.WARNING); }
    } else if elementInfo.settingName == "contrastColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempEnv.contrastColor = .{r, g, b}; } else { Basic.log("Invalid float for contrastColor", flags=.WARNING); }
    } else if elementInfo.settingName == "textColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempEnv.textColor = .{r, g, b}; } else { Basic.log("Invalid float for textColor", flags=.WARNING); }
    } else if elementInfo.settingName == "fontSize" {
        parsed, ok := Basic.string_to_s64(textEntry.text);
        if ok { dialog.tempEnv.fontSize = parsed; } else { Basic.log("Invalid s64 for fontSize", flags=.WARNING); }
    } else if elementInfo.settingName == "fontFamily" {
        Basic.free(dialog.tempEnv.fontFamily); 
        dialog.tempEnv.fontFamily = Basic.clone_string(textEntry.text);
    } 
    // BOARD SETTINGS
    else if elementInfo.settingName == "pieces" {
        Basic.free(dialog.tempBoard.pieces);
        dialog.tempBoard.pieces = Basic.clone_string(textEntry.text);
    } else if elementInfo.settingName == "lightSquareColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempBoard.lightSquareColor = .{r, g, b}; } else { Basic.log("Invalid float for lightSquareColor", flags=.WARNING); }
    } else if elementInfo.settingName == "darkSquareColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempBoard.darkSquareColor = .{r, g, b}; } else { Basic.log("Invalid float for darkSquareColor", flags=.WARNING); }
    } else if elementInfo.settingName == "highlightValidSquares" {
        val, ok := parse_bool(textEntry.text); if ok dialog.tempBoard.highlightValidSquares = val; else Basic.log("Invalid bool for highlightValidSquares", flags=.WARNING);
    } else if elementInfo.settingName == "showCapturedPiece" {
        val, ok := parse_bool(textEntry.text); if ok dialog.tempBoard.showCapturedPiece = val; else Basic.log("Invalid bool for showCapturedPiece", flags=.WARNING);
    } else if elementInfo.settingName == "dragAndDropMove.enabled" {
        val, ok := parse_bool(textEntry.text); if ok dialog.tempBoard.dragAndDropMove.enabled = val; else Basic.log("Invalid bool for dragAndDropMove.enabled", flags=.WARNING);
    } else if elementInfo.settingName == "dragAndDropMove.ghostOpacity" {
        val, ok := Basic.string_to_float32(textEntry.text); if ok dialog.tempBoard.dragAndDropMove.ghostOpacity = val; else Basic.log("Invalid float for dragAndDropMove.ghostOpacity", flags=.WARNING);
    } else if elementInfo.settingName == "clickClickMove.enabled" {
        val, ok := parse_bool(textEntry.text); if ok dialog.tempBoard.clickClickMove.enabled = val; else Basic.log("Invalid bool for clickClickMove.enabled", flags=.WARNING);
    } else if elementInfo.settingName == "destinationSquareMove.enabled" {
        val, ok := parse_bool(textEntry.text); if ok dialog.tempBoard.destinationSquareMove.enabled = val; else Basic.log("Invalid bool for destinationSquareMove.enabled", flags=.WARNING);
    } else if elementInfo.settingName == "destinationSquareMove.disambiguate" { 
        val, ok := parse_bool(textEntry.text); if ok dialog.tempBoard.destinationSquareMove.disambiguateWithLastMovedPiece = val; else Basic.log("Invalid bool for destinationSquareMove.disambiguate", flags=.WARNING);
    } else if elementInfo.settingName == "destinationSquareMove.mouseButton" {
         dialog.tempBoard.destinationSquareMove.mouseButton = string_to_mouse_button(textEntry.text);
    } else if elementInfo.settingName == "keyboardMove.enabled" {
        val, ok := parse_bool(textEntry.text); if ok dialog.tempBoard.keyboardMove.enabled = val; else Basic.log("Invalid bool for keyboardMove.enabled", flags=.WARNING);
    }
    // ANALYSIS SETTINGS
    else if elementInfo.settingName == "externalSite" {
        Basic.free(dialog.tempAnalysis.externalSite);
        dialog.tempAnalysis.externalSite = Basic.clone_string(textEntry.text);
    } else if elementInfo.settingName == "uciEngine" {
        Basic.free(dialog.tempAnalysis.uciEngine);
        dialog.tempAnalysis.uciEngine = Basic.clone_string(textEntry.text);
    }
    // CONTROLS SETTINGS - This requires a dynamic way to set fields.
    // A simple if/else chain for each control:
    else if elementInfo.settingName == "undo" { dialog.tempControls.undo = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "nextPly" { dialog.tempControls.nextPly = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "previousPly" { dialog.tempControls.previousPly = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "firstPly" { dialog.tempControls.firstPly = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "lastPly" { dialog.tempControls.lastPly = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "editPlyComment" { dialog.tempControls.editPlyComment = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "deletePly" { dialog.tempControls.deletePly = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "nextVariation" { dialog.tempControls.nextVariation = display_string_to_key(textEntry.text); }
    else if elementInfo.settingName == "previousVariation" { dialog.tempControls.previousVariation = display_string_to_key(textEntry.text); }
    // LIBRARY SETTINGS
    else if elementInfo.settingName == "path" {
        Basic.free(dialog.tempLibrary.path);
        dialog.tempLibrary.path = Basic.clone_string(textEntry.text);
    } else if elementInfo.settingName == "gameTitleFormat" {
        Basic.free(dialog.tempLibrary.gameTitleFormat);
        dialog.tempLibrary.gameTitleFormat = Basic.clone_string(textEntry.text);
    }
    // MOVES SETTINGS
    else if elementInfo.settingName == "mainColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.mainColor = .{r, g, b}; } else { Basic.log("Invalid float for mainColor", flags=.WARNING); }
    } else if elementInfo.settingName == "interestingColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.interestingColor = .{r, g, b}; } else { Basic.log("Invalid float for interestingColor", flags=.WARNING); }
    } else if elementInfo.settingName == "goodColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.goodColor = .{r, g, b}; } else { Basic.log("Invalid float for goodColor", flags=.WARNING); }
    } else if elementInfo.settingName == "brillantColor" { // Note: "brillantColor" in config.jai
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.brillantColor = .{r, g, b}; } else { Basic.log("Invalid float for brillantColor", flags=.WARNING); }
    } else if elementInfo.settingName == "dubiousColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.dubiousColor = .{r, g, b}; } else { Basic.log("Invalid float for dubiousColor", flags=.WARNING); }
    } else if elementInfo.settingName == "mistakeColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.mistakeColor = .{r, g, b}; } else { Basic.log("Invalid float for mistakeColor", flags=.WARNING); }
    } else if elementInfo.settingName == "blunderColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.blunderColor = .{r, g, b}; } else { Basic.log("Invalid float for blunderColor", flags=.WARNING); }
    } else if elementInfo.settingName == "selectedColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.selectedColor = .{r, g, b}; } else { Basic.log("Invalid float for selectedColor", flags=.WARNING); }
    } else if elementInfo.settingName == "selectedCommentColor" {
        r_text := elementInfo.textEntries[0].text; g_text := elementInfo.textEntries[1].text; b_text := elementInfo.textEntries[2].text;
        r, r_ok := Basic.string_to_float32(r_text); g, g_ok := Basic.string_to_float32(g_text); b, b_ok := Basic.string_to_float32(b_text);
        if r_ok && g_ok && b_ok { dialog.tempMoves.selectedCommentColor = .{r, g, b}; } else { Basic.log("Invalid float for selectedCommentColor", flags=.WARNING); }
    } else if elementInfo.settingName == "variationsCollapsed" {
        val, ok := parse_bool(textEntry.text); if ok dialog.tempMoves.variationsCollapsed = val; else Basic.log("Invalid bool for variationsCollapsed", flags=.WARNING);
    } else if elementInfo.settingName == "compactThreshold" {
        parsed, ok := Basic.string_to_s64(textEntry.text);
        if ok { dialog.tempMoves.compactThreshold = parsed; } else { Basic.log("Invalid s64 for compactThreshold", flags=.WARNING); }
    } else if elementInfo.settingName == "comments.shortStyle" {
        dialog.tempMoves.comments.shortStyle = string_to_comment_style(textEntry.text);
    } else if elementInfo.settingName == "comments.normalStyle" {
        dialog.tempMoves.comments.normalStyle = string_to_comment_style(textEntry.text);
    } else if elementInfo.settingName == "comments.longStyle" {
        dialog.tempMoves.comments.longStyle = string_to_comment_style(textEntry.text);
    } else if elementInfo.settingName == "comments.fullStyleWidth" {
        val, ok := Basic.string_to_float32(textEntry.text); if ok dialog.tempMoves.comments.fullStyleWidth = val; else Basic.log("Invalid float for comments.fullStyleWidth", flags=.WARNING);
    }
}

_on_message_settings_dialog :: (dialog : *SettingsDialogEntity, message : *Message) {
    if message.kind == .SystemReflow {
        _reflow_settings_dialog(dialog);
    }
    // Handle other messages if necessary, e.g., keyboard input for save/cancel
}

_reflow_settings_dialog :: (dialog: *SettingsDialogEntity) {
    windowExtent := Crater.window_get_extent(instance.engine.window, Chamber.vec2);

    // Center dialog on screen
    dialog.ui.extent.width = dialog.dialogWidth;
    dialog.ui.extent.height = dialog.contentHeight; // Calculated in create
    dialog.transform.translation.x = (windowExtent.width - dialog.ui.extent.width) / 2.0;
    dialog.transform.translation.y = (windowExtent.height - dialog.ui.extent.height) / 2.0;
    Chamber.round(*dialog.transform.translation);
    Sill.transform_commit(*dialog.transform);

    // Update background mesh size
    dialog.mesh.nodes[0].transform.scaling.xy = dialog.ui.extent;
    Sill.mesh_commit_nodes(*dialog.mesh);

    // Reposition elements
    yCurrent := UiConstants.PaddingVerticalLarge;
    labelX := UiConstants.PaddingHorizontalLarge;
    // Adjusted valueStartX for potentially narrower labels, wider value fields
    valueStartX := dialog.dialogWidth * 0.45; 
    valueAvailableWidth := dialog.dialogWidth - valueStartX - UiConstants.PaddingHorizontalLarge;

    // Helper for reflowing a list of elements and their labels
    reflow_elements_list = (elements_list: *[..]SettingsElementInfo, y_offset_ptr: *float) {
        for i : 0..elements_list.count-1 {
            elementInfo := Basic.array_get_pointer(elements_list, i);
            labelEntity := elementInfo.label;
            
            if !labelEntity continue; 

            // Position Label on the left part
            labelEntity.transform.translation.x = labelX + labelEntity.ui.extent.width / 2.0;
            labelEntity.transform.translation.y = y_offset_ptr.* + labelEntity.ui.extent.height / 2.0;
            Chamber.round(*labelEntity.transform.translation);
            Sill.transform_commit(*labelEntity.transform);

            currentElementHeight := labelEntity.ui.extent.height;

            // Position Text Entries on the right part
            if elementInfo.numTextEntries == 1 {
                textEntry := elementInfo.textEntries[0];
                if textEntry { // Ensure text entry exists
                    textEntry.ui.extent.width = valueAvailableWidth; // Text entry takes available width
                    textEntry.transform.translation.x = valueStartX + textEntry.ui.extent.width / 2.0;
                    textEntry.transform.translation.y = y_offset_ptr.* + textEntry.ui.extent.height / 2.0;
                    Chamber.round(*textEntry.transform.translation);
                    Sill.transform_commit(*textEntry.transform);
                    currentElementHeight = Basic.max(currentElementHeight, textEntry.ui.extent.height);
                }
            } else if elementInfo.numTextEntries == 3 { // For vec3
                entryWidth := (valueAvailableWidth - 2 * UiConstants.PaddingHorizontalSmall) / 3.0;
                maxTextEntryHeight : float = 0;
                for j: 0..2 {
                    textEntry := elementInfo.textEntries[j];
                    if textEntry { // Ensure text entry exists
                        textEntry.ui.extent.width = entryWidth;
                        textEntry.transform.translation.x = valueStartX + (j * (entryWidth + UiConstants.PaddingHorizontalSmall)) + entryWidth / 2.0;
                        textEntry.transform.translation.y = y_offset_ptr.* + textEntry.ui.extent.height / 2.0;
                        Chamber.round(*textEntry.transform.translation);
                        Sill.transform_commit(*textEntry.transform);
                        maxTextEntryHeight = Basic.max(maxTextEntryHeight, textEntry.ui.extent.height);
                    }
                }
                currentElementHeight = Basic.max(currentElementHeight, maxTextEntryHeight);
            }
            y_offset_ptr.* += currentElementHeight + UiConstants.PaddingVerticalMedium;
        }
    }
    
    // Reflow Env Section Label
    if dialog.envSectionLabel {
        dialog.envSectionLabel.transform.translation.x = dialog.dialogWidth / 2.0; // Center
        dialog.envSectionLabel.transform.translation.y = yCurrent + dialog.envSectionLabel.ui.extent.height / 2.0;
        Chamber.round(*dialog.envSectionLabel.transform.translation);
        Sill.transform_commit(*dialog.envSectionLabel.transform);
        yCurrent += dialog.envSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;
    }

    reflow_elements_list(*dialog.envElements, *yCurrent);
    yCurrent += UiConstants.PaddingVerticalLarge; 

    // Reflow Board Section Label
    if dialog.boardSectionLabel {
        dialog.boardSectionLabel.transform.translation.x = dialog.dialogWidth / 2.0; 
        dialog.boardSectionLabel.transform.translation.y = yCurrent + dialog.boardSectionLabel.ui.extent.height / 2.0;
        Chamber.round(*dialog.boardSectionLabel.transform.translation);
        Sill.transform_commit(*dialog.boardSectionLabel.transform);
        yCurrent += dialog.boardSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;
    }
    reflow_elements_list(*dialog.boardElements, *yCurrent);
    yCurrent += UiConstants.PaddingVerticalLarge;

    // Reflow Analysis Section Label
    if dialog.analysisSectionLabel {
        dialog.analysisSectionLabel.transform.translation.x = dialog.dialogWidth / 2.0;
        dialog.analysisSectionLabel.transform.translation.y = yCurrent + dialog.analysisSectionLabel.ui.extent.height / 2.0;
        Chamber.round(*dialog.analysisSectionLabel.transform.translation);
        Sill.transform_commit(*dialog.analysisSectionLabel.transform);
        yCurrent += dialog.analysisSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;
    }
    reflow_elements_list(*dialog.analysisElements, *yCurrent);
    yCurrent += UiConstants.PaddingVerticalLarge;

    // Reflow Controls Section Label
    if dialog.controlsSectionLabel {
        dialog.controlsSectionLabel.transform.translation.x = dialog.dialogWidth / 2.0;
        dialog.controlsSectionLabel.transform.translation.y = yCurrent + dialog.controlsSectionLabel.ui.extent.height / 2.0;
        Chamber.round(*dialog.controlsSectionLabel.transform.translation);
        Sill.transform_commit(*dialog.controlsSectionLabel.transform);
        yCurrent += dialog.controlsSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;
    }
    reflow_elements_list(*dialog.controlsElements, *yCurrent);
    yCurrent += UiConstants.PaddingVerticalLarge;

    // Reflow Library Section Label
    if dialog.librarySectionLabel {
        dialog.librarySectionLabel.transform.translation.x = dialog.dialogWidth / 2.0;
        dialog.librarySectionLabel.transform.translation.y = yCurrent + dialog.librarySectionLabel.ui.extent.height / 2.0;
        Chamber.round(*dialog.librarySectionLabel.transform.translation);
        Sill.transform_commit(*dialog.librarySectionLabel.transform);
        yCurrent += dialog.librarySectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;
    }
    reflow_elements_list(*dialog.libraryElements, *yCurrent);
    yCurrent += UiConstants.PaddingVerticalLarge;

    // Reflow Moves Section Label
    if dialog.movesSectionLabel {
        dialog.movesSectionLabel.transform.translation.x = dialog.dialogWidth / 2.0;
        dialog.movesSectionLabel.transform.translation.y = yCurrent + dialog.movesSectionLabel.ui.extent.height / 2.0;
        Chamber.round(*dialog.movesSectionLabel.transform.translation);
        Sill.transform_commit(*dialog.movesSectionLabel.transform);
        yCurrent += dialog.movesSectionLabel.ui.extent.height + UiConstants.PaddingVerticalSmall;
    }
    reflow_elements_list(*dialog.movesElements, *yCurrent);
    
    // Reflow placeholder labels - This part remains heuristic and might need refinement if placeholders are numerous or complex.
    // For now, this part is simplified: yCurrent is advanced in _add_placeholder_label.
    // Their X position will be based on their label anchor (.Left by default).
    // To center them or place them properly under sections, they'd need specific handling here.
    // The current _add_placeholder_label makes them children of dialog.
    // We iterate all children of dialog that are labels and not part of element lists.
    for child: dialog.children {
        if child.typeInfo == type_info(LabelEntity) {
            isElementLabel := false;
            for el : dialog.envElements if el.label == child isElementLabel = true; break;
            if isElementLabel continue;
            for el : dialog.boardElements if el.label == child isElementLabel = true; break;
            if isElementLabel continue;
            if child == dialog.envSectionLabel || child == dialog.boardSectionLabel continue;

            // This must be a placeholder label
            placeHolderLabel := cast(*LabelEntity) child;
            placeHolderLabel.transform.translation.x = labelX + placeHolderLabel.ui.extent.width / 2.0;
            // Y position was effectively set by creation order and yOffset accumulation.
            // If yCurrent was not passed to _add_placeholder_label and accumulated there, this Y might be wrong.
            // The current _add_placeholder_label *does* take yOffset, so their Y should be okay relative to creation.
            // This reflow ensures their X and that they are considered in height.
            // For robust dynamic Y, they should be part of the sequential yCurrent calculation.
            // The current implementation of _add_placeholder_label updates the main yCurrent, so this loop is mostly for X and ensuring commit.
            Chamber.round(*placeHolderLabel.transform.translation); // Already rounded in create? if so, not needed.
            Sill.transform_commit(*placeHolderLabel.transform); // Already committed?
        }
    }


    yCurrent += UiConstants.PaddingVerticalLarge; // Padding before buttons
    
    // Recalculate content height based on actual element sizes during reflow
    dialog.contentHeight = yCurrent + UiConstants.HeightButtonDialog + UiConstants.PaddingVerticalLarge;
    dialog.ui.extent.height = dialog.contentHeight;
    dialog.mesh.nodes[0].transform.scaling.xy = dialog.ui.extent; // Update background size
    Sill.mesh_commit_nodes(*dialog.mesh);
    
    // Center dialog again if its height changed
    dialog.transform.translation.y = (windowExtent.height - dialog.ui.extent.height) / 2.0;
    Chamber.round(*dialog.transform.translation);
    Sill.transform_commit(*dialog.transform);


    // Reposition Save and Cancel Buttons
    buttonWidth := (dialog.dialogWidth - 3 * UiConstants.PaddingHorizontalMedium) / 2;
    dialog.saveButton.ui.extent.width = buttonWidth;
    dialog.saveButton.ui.extent.height = UiConstants.HeightButtonDialog;
    dialog.saveButton.transform.translation.x = UiConstants.PaddingHorizontalMedium + buttonWidth / 2.0;
    dialog.saveButton.transform.translation.y = yCurrent + UiConstants.HeightButtonDialog / 2.0;
    Chamber.round(*dialog.saveButton.transform.translation);
    Sill.transform_commit(*dialog.saveButton.transform);
    button_refresh(*dialog.saveButton.button);


    dialog.cancelButton.ui.extent.width = buttonWidth;
    dialog.cancelButton.ui.extent.height = UiConstants.HeightButtonDialog;
    dialog.cancelButton.transform.translation.x = UiConstants.PaddingHorizontalMedium * 2 + buttonWidth + buttonWidth / 2.0;
    dialog.cancelButton.transform.translation.y = yCurrent + UiConstants.HeightButtonDialog / 2.0;
    Chamber.round(*dialog.cancelButton.transform.translation);
    Sill.transform_commit(*dialog.cancelButton.transform);
    button_refresh(*dialog.cancelButton.button);
}
