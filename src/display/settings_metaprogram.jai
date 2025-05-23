#import "Basic";      // For String_Builder, tprint, type_info, Type_Info_Member, etc.
#import "Chamber";    // For vec3, vec4
#import "Crater";     // For Key, MouseButton
#import "..structures.config"; // For Config struct and its sub-structs like ConfigEnv, ConfigBoard, etc.
#import "..structures.game";   // For CommentStyle

// --- Forward Declarations for Metaprogram Functions ---
generate_ui_for_struct_members_in_builder :: (builder: *String_Builder, struct_ti: *Type_Info_Struct, dialog_var_name: string, temp_struct_base_path: string, y_offset_var_name: string, unique_id_counter: *u32, all_callbacks_builder: *String_Builder) #modify;
generate_ui_for_struct_member :: (builder: *String_Builder, member: Type_Info_Member, dialog_var_name: string, temp_struct_base_path: string, current_field_path: string, y_offset_var_name: string, enclosing_struct_ti: *Type_Info_Struct, unique_id_counter: *u32, all_callbacks_builder: *String_Builder) #modify;
generate_field_update_callback :: (builder: *String_Builder, member: Type_Info_Member, temp_struct_base_path: string, current_field_path: string, enclosing_struct_ti: *Type_Info_Struct, unique_id: u32, component_name_opt: string = "") #modify;

// --- Metaprogram Core ---

generate_member_callback_name :: (base_path: string, member_name: string, unique_id: u32, component_name_opt: string = "") -> string {
    clean_base := Basic.replace_all(base_path, ".", "_");
    clean_member_name := Basic.replace_all(member_name, ".", "_"); 
    if component_name_opt == ""
        return Basic.tprint("_mp_cb_%s_%s_%u", clean_base, clean_member_name, unique_id);
    else
        return Basic.tprint("_mp_cb_%s_%s_%s_%u", clean_base, clean_member_name, component_name_opt, unique_id);
}

#modify generate_field_update_callback :: (builder: *String_Builder, member: Type_Info_Member, temp_struct_base_path: string, current_field_path: string, enclosing_struct_ti: *Type_Info_Struct, unique_id: u32, component_name_opt: string = "") {
    callback_name := generate_member_callback_name(temp_struct_base_path, member.name, unique_id, component_name_opt);
    
    if member.type == type_info(bool) {
        Basic.append(builder, tprint("\n%s :: (new_bool_value: bool, target_field_ptr_raw: *void) {\n", callback_name)); // Expects bool
        Basic.append(builder, tprint("    // Metaprogram-generated callback for %s (bool toggle)\n", current_field_path));
        Basic.append(builder, tprint("    target_field_ptr := cast(*bool) target_field_ptr_raw;\n"));
        Basic.append(builder, tprint("    <<target_field_ptr = new_bool_value;\n"));
        Basic.append(builder, "}\n");
        return; 
    }

    Basic.append(builder, tprint("\n%s :: (new_value_str: string, target_field_ptr_raw: *void) {\n", callback_name));
    Basic.append(builder, tprint("    // Metaprogram-generated callback for %s (component: %s)\n", current_field_path, ifx component_name_opt != "" then component_name_opt else "N/A"));

    if member.type == type_info(string) {
        Basic.append(builder, tprint("    target_field_ptr := cast(*string) target_field_ptr_raw;\n"));
        Basic.append(builder, tprint("    Basic.free(<<target_field_ptr);\n"));
        Basic.append(builder, tprint("    <<target_field_ptr = Basic.clone_string(new_value_str);\n"));
    } else if member.type == type_info(s64) {
        Basic.append(builder, tprint("    target_field_ptr := cast(*s64) target_field_ptr_raw;\n"));
        Basic.append(builder, tprint("    parsed_val, ok := Basic.string_to_s64(new_value_str);\n"));
        Basic.append(builder, tprint("    if ok then <<target_field_ptr = parsed_val;\n"));
        Basic.append(builder, tprint("    else Basic.log_warning(\"[Settings Metaprogram] Invalid s64 input: '%' for %s\", new_value_str, \"%s\");\n", member.name));
    } else if member.type == type_info(float) { 
        Basic.append(builder, tprint("    target_field_ptr := cast(*float) target_field_ptr_raw;\n"));
        Basic.append(builder, tprint("    parsed_val, ok := Basic.string_to_float32(new_value_str);\n"));
        Basic.append(builder, tprint("    if ok then <<target_field_ptr = parsed_val;\n"));
        Basic.append(builder, tprint("    else Basic.log_warning(\"[Settings Metaprogram] Invalid float input: '%' for %s\", new_value_str, \"%s\");\n", member.name));
    } else if member.type == type_info(Chamber.vec3) || member.type == type_info(Chamber.vec4) { 
        Basic.assert(component_name_opt != "", "Component name must be provided for vec types in callback.");
        Basic.append(builder, tprint("    target_vec_ptr := cast(*%s) target_field_ptr_raw;\n", member.type.name)); 
        Basic.append(builder, tprint("    parsed_val, ok := Basic.string_to_float32(new_value_str);\n"));
        Basic.append(builder, tprint("    if ok then target_vec_ptr.%s = parsed_val;\n", component_name_opt)); 
        Basic.append(builder, tprint("    else Basic.log_warning(\"[Settings Metaprogram] Invalid float input for component %s.%s: '%'\", \"%s\", \"%s\", new_value_str);\n", member.name, component_name_opt));
    } 
    // Bool handled above
    else if member.type.type == .ENUM {
        enum_ti := cast(*Type_Info_Enum) member.type;
        Basic.append(builder, tprint("    target_field_ptr := cast(*%s) target_field_ptr_raw;\n", enum_ti.name));
        if enum_ti.name == "Crater.MouseButton"  Basic.append(builder, "    <<target_field_ptr = string_to_mouse_button_runtime(new_value_str);\n");
        else if enum_ti.name == "CommentStyle" Basic.append(builder, "    <<target_field_ptr = string_to_comment_style_runtime(new_value_str);\n");
        else if enum_ti.name == "Crater.Key"   Basic.append(builder, "    <<target_field_ptr = display_string_to_key_runtime(new_value_str);\n"); 
        else Basic.append(builder, tprint("    // [Settings Metaprogram] Unknown enum type for string_to_enum: %\n", enum_ti.name));
    } else {
        Basic.append(builder, tprint("    // [Settings Metaprogram] No parsing logic for type % in this callback for field %\n", member.type.name, member.name));
    }
    Basic.append(builder, "}\n");
}


#modify generate_ui_for_struct_member :: (builder: *String_Builder, member: Type_Info_Member, dialog_var_name: string, temp_struct_base_path: string, current_field_path: string, y_offset_var_name: string, enclosing_struct_ti: *Type_Info_Struct, unique_id_counter: *u32, all_callbacks_builder: *String_Builder) {
    Basic.assert(member.type != null, "Member % of struct % has null type_info.", member.name, enclosing_struct_ti.name);
    
    member_label_text_raw := member.name;
    if temp_struct_base_path.count > 0 {
        parts := Basic.split_string(temp_struct_base_path, ".");
        if parts.count > 2 { 
            parent_struct_name := parts[parts.count-1];
            if Basic.ends_with(parent_struct_name, "Move") { 
                 if member.name == "enabled" member_label_text_raw = ""; 
                 else if member.name == "ghostOpacity" member_label_text_raw = "Ghost Opacity";
                 else if member.name == "disambiguateWithLastMovedPiece" member_label_text_raw = "Disambiguate";
                 else if member.name == "mouseButton" member_label_text_raw = "Mouse Button";
            }
            if parent_struct_name == "comments" {
                if member.name == "shortStyle" member_label_text_raw = "Short Style";
                else if member.name == "normalStyle" member_label_text_raw = "Normal Style";
                else if member.name == "longStyle" member_label_text_raw = "Long Style";
                else if member.name == "fullStyleWidth" member_label_text_raw = "Full Style Width";
            }
        }
    }
    
    member_label_text := Basic.replace_all(member_label_text_raw, "_", " ");
    member_label_text_parts := Basic.split_string(member_label_text, " ");
    for i: 0..member_label_text_parts.count-1 {
        if member_label_text_parts[i].count > 0 {
            member_label_text_parts[i][0] = Basic.char_to_upper(member_label_text_parts[i][0]);
        }
    }
    if member_label_text_parts.count > 0 member_label_text = Basic.join_strings(member_label_text_parts, " ");
    else member_label_text = ""; 

    member_type := member.type;
    full_field_access_path_str := current_field_path; 

    if member_type == type_info(Chamber.vec3) || member_type == type_info(Chamber.vec4) {
        Basic.append(builder, tprint("    _mp_rt_add_label(%s, \"%s\", %s, false, true);\n", dialog_var_name, member_label_text, y_offset_var_name));
        components := ifx member_type == type_info(Chamber.vec3) then .["x", "y", "z"] else .["x", "y", "z", "w"];
        for component_name: components {
            uid_comp := <<unique_id_counter; <<unique_id_counter += 1; 
            callback_name_comp := generate_member_callback_name(temp_struct_base_path, member.name, uid_comp, component_name);
            
            Basic.append(builder, tprint("    _mp_rt_create_float_entry(%s, \"%s\", %s.%s, %s, &%s, cast(*void) *%s, true);\n", 
                dialog_var_name, component_name, full_field_access_path_str, component_name, y_offset_var_name, callback_name_comp, full_field_access_path_str));
        }
    } else if member_type == type_info(bool) { 
        uid := <<unique_id_counter; <<unique_id_counter += 1;
        callback_proc_name := generate_member_callback_name(temp_struct_base_path, member.name, uid);
        Basic.append(builder, tprint("    _mp_rt_create_bool_toggle_button(%s, \"%s\", %s, %s, &%s, cast(*void) *%s);\n", 
            dialog_var_name, member_label_text, full_field_access_path_str, y_offset_var_name, callback_proc_name, full_field_access_path_str));
    } else if member_type.type == .STRUCT {
        nested_struct_ti := cast(*Type_Info_Struct) member_type;
        if member_label_text != "" Basic.append(builder, tprint("    _mp_rt_add_section_label(%s, \"%s\", %s, true);\n", dialog_var_name, member_label_text, y_offset_var_name));
        generate_ui_for_struct_members_in_builder(builder, nested_struct_ti, dialog_var_name, full_field_access_path_str, y_offset_var_name, unique_id_counter, all_callbacks_builder);
    } else if member_type.type == .ARRAY {
         Basic.append(builder, tprint("    _mp_rt_add_array_placeholder_entry(%s, \"%s\", %s);\n", 
            dialog_var_name, member_label_text, y_offset_var_name));
    } else { 
        uid := <<unique_id_counter; <<unique_id_counter += 1;
        callback_proc_name := generate_member_callback_name(temp_struct_base_path, member.name, uid);
        
        if member_type == type_info(string) {
            Basic.append(builder, tprint("    _mp_rt_create_string_entry(%s, \"%s\", %s, %s, &%s, cast(*void) *%s);\n", 
                dialog_var_name, member_label_text, full_field_access_path_str, y_offset_var_name, callback_proc_name, full_field_access_path_str));
        } else if member_type == type_info(s64) {
            Basic.append(builder, tprint("    _mp_rt_create_s64_entry(%s, \"%s\", %s, %s, &%s, cast(*void) *%s);\n", 
                dialog_var_name, member_label_text, full_field_access_path_str, y_offset_var_name, callback_proc_name, full_field_access_path_str));
        } else if member_type == type_info(float) {
             Basic.append(builder, tprint("    _mp_rt_create_float_entry(%s, \"%s\", %s, %s, &%s, cast(*void) *%s);\n", 
                dialog_var_name, member_label_text, full_field_access_path_str, y_offset_var_name, callback_proc_name, full_field_access_path_str));
        } 
        else if member_type.type == .ENUM {
            enum_ti := cast(*Type_Info_Enum) member_type;
            enum_to_string_helper_name := "";
            if enum_ti.name == "Crater.MouseButton"  enum_to_string_helper_name = "mouse_button_to_string_runtime";
            else if enum_ti.name == "CommentStyle" enum_to_string_helper_name = "comment_style_to_string_runtime";
            else if enum_ti.name == "Crater.Key"   enum_to_string_helper_name = "key_to_display_string_runtime"; 
            else enum_to_string_helper_name = "unknown_enum_to_string_runtime"; 

            Basic.append(builder, tprint("    _mp_rt_create_enum_entry(%s, \"%s\", %s(%s), %s, &%s, cast(*void) *%s, \"%s\");\n", 
                dialog_var_name, member_label_text, enum_to_string_helper_name, full_field_access_path_str, y_offset_var_name, callback_proc_name, full_field_access_path_str, enum_ti.name));
        } else {
            Basic.append(builder, tprint("    // [Settings Metaprogram] Unsupported simple type for member '%s': %s\n", member.name, member_type.name));
        }
    }
}

#modify generate_ui_for_struct_members_in_builder :: (builder: *String_Builder, struct_ti: *Type_Info_Struct, dialog_var_name: string, temp_struct_base_path: string, y_offset_var_name: string, unique_id_counter: *u32, all_callbacks_builder: *String_Builder) {
    if struct_ti == null {
        Basic.append(builder, "    // Error: struct_type_info is null in generate_ui_for_struct_members_in_builder\n");
        return;
    }
    if struct_ti.members.count == 0 {
         Basic.append(builder, tprint("    // Struct %s has no members to generate UI for.\n", struct_ti.name));
         return;
    }
    for member: struct_ti.members {
        current_field_path := tprint("%s.%s", temp_struct_base_path, member.name);
        generate_ui_for_struct_member(builder, member, dialog_var_name, temp_struct_base_path, current_field_path, y_offset_var_name, struct_ti, unique_id_counter, all_callbacks_builder);
    }
}

#modify generate_callbacks_for_struct_recursive :: (builder: *String_Builder, struct_ti: *Type_Info_Struct, temp_struct_base_path: string, unique_id_counter: *u32) {
    for member: struct_ti.members {
        current_field_path := tprint("%s.%s", temp_struct_base_path, member.name);
        if member.type.type == .STRUCT {
            nested_struct_ti := cast(*Type_Info_Struct) member.type;
            generate_callbacks_for_struct_recursive(builder, nested_struct_ti, current_field_path, unique_id_counter);
        } else if member.type == type_info(Chamber.vec3) || member.type == type_info(Chamber.vec4) {
            components := ifx member.type == type_info(Chamber.vec3) then .["x", "y", "z"] else .["x", "y", "z", "w"];
            for component_name: components {
                uid_comp := <<unique_id_counter; <<unique_id_counter += 1;
                generate_field_update_callback(builder, member, current_field_path, current_field_path, struct_ti, uid_comp, component_name);
            }
        } else if member.type.type != .ARRAY { 
            uid := <<unique_id_counter; <<unique_id_counter += 1;
            generate_field_update_callback(builder, member, temp_struct_base_path, current_field_path, struct_ti, uid);
        }
    }
}


// Top-level metaprogram procedure
generate_all_settings_sections_code :: (runtime_helpers_module_path: string = "") -> string { 
    main_builder: String_Builder; Basic.init_string_builder(*main_builder);
    callbacks_builder: String_Builder; Basic.init_string_builder(*callbacks_builder);
    
    unique_id_counter : u32 = 0;

    Basic.append(*main_builder, "// --- METAPROGRAM GENERATED CODE (START) ---\n");
    Basic.append(*main_builder, "#import \"Basic\";\n");
    Basic.append(*main_builder, "#import \"Chamber\";\n");
    Basic.append(*main_builder, "#import \"Crater\";\n");
    Basic.append(*main_builder, "#import \"..structures.config\";\n"); 
    Basic.append(*main_builder, "#import \"..structures.game\";\n");   
    Basic.append(*main_builder, "#import \"src.display.UiConstants\";\n"); 
    if runtime_helpers_module_path != "" Basic.append(*main_builder, tprint("#import \"%s\";\n", runtime_helpers_module_path));
    Basic.append(*main_builder, "SettingsDialogEntity :: import \"src.display.settings_dialog\".SettingsDialogEntity;\n\n"); 
    
    Basic.append(*main_builder, "// Runtime Enum/Parsing Helper Forward Declarations (must be implemented where this code is inserted)\n");
    // Basic.append(*main_builder, "parse_bool_runtime :: (text: string) -> bool, bool #foreign;\n"); // No longer needed for bool callbacks
    Basic.append(*main_builder, "string_to_mouse_button_runtime :: (s: string) -> Crater.MouseButton #foreign;\n");
    Basic.append(*main_builder, "string_to_comment_style_runtime :: (s: string) -> CommentStyle #foreign;\n");    
    Basic.append(*main_builder, "key_to_display_string_runtime :: (key: Crater.Key) -> string #foreign;\n"); 
    Basic.append(*main_builder, "display_string_to_key_runtime :: (s: string) -> Crater.Key #foreign;\n");      
    Basic.append(*main_builder, "mouse_button_to_string_runtime :: (mb: Crater.MouseButton) -> string #foreign;\n"); 
    Basic.append(*main_builder, "comment_style_to_string_runtime :: (style: CommentStyle) -> string #foreign;\n");
    Basic.append(*main_builder, "unknown_enum_to_string_runtime :: (val: s64) -> string #foreign { return \"Unknown Enum\"; }\n\n");


    Basic.append(*callbacks_builder, "// --- Generated Callbacks ---\n");
    config_ti := type_info(Config);
    config_struct_ti := cast(*Type_Info_Struct) config_ti;
    
    for section_member: config_struct_ti.members { 
        if section_member.type.type != .STRUCT continue;
        section_struct_ti := cast(*Type_Info_Struct) section_member.type;
        
        section_name_pascal_case := tprint("%s%s", Basic.toupper(section_member.name[0]), Basic.substring(section_member.name, 1, section_member.name.count-1));
        temp_section_instance_path := tprint("dialog.temp%s", section_name_pascal_case); 
        
        generate_callbacks_for_struct_recursive(callbacks_builder, section_struct_ti, temp_section_instance_path, *unique_id_counter);
    }
    Basic.append(*callbacks_builder, "\n// --- End Generated Callbacks ---\n\n");
    Basic.append_builder(main_builder, *callbacks_builder); 

    Basic.append(*main_builder, "// --- Generated UI Creation Procedures ---\n");
    for section_member: config_struct_ti.members {
        if section_member.type.type != .STRUCT continue; 

        section_name_pascal_case := tprint("%s%s", Basic.toupper(section_member.name[0]), Basic.substring(section_member.name, 1, section_member.name.count-1));
        proc_name := tprint("_mp_generate_ui_for_%s_section", section_member.name);
        temp_struct_instance_path := tprint("dialog.temp%s", section_name_pascal_case);
        
        Basic.append(*main_builder, tprint("%s :: (dialog: *SettingsDialogEntity, yOffset: *float) {\n", proc_name));
        Basic.append(*main_builder, tprint("    _mp_rt_add_section_label(dialog, \"%s Settings\", yOffset);\n", section_name_pascal_case));
        
        section_struct_ti := cast(*Type_Info_Struct) section_member.type;
        generate_ui_for_struct_members_in_builder(*main_builder, section_struct_ti, "dialog", temp_struct_instance_path, "yOffset", *unique_id_counter, *callbacks_builder); 
        
        Basic.append(*main_builder, "}\n\n");
    }
    Basic.append(*main_builder, "// --- End Generated UI Creation Procedures ---\n\n");
    Basic.append(*main_builder, "// --- METAPROGRAM GENERATED CODE (END) ---\n");

    return Basic.to_string(main_builder);
}

// Stubs for runtime helpers, just for the #run block below to work without full runtime.
_mp_rt_add_label :: (dialog: *SettingsDialogEntity, text: string, yOffset_ptr: *float, is_main_label: bool = false, is_sub_header: bool = false) #foreign {}
_mp_rt_add_section_label :: (dialog: *SettingsDialogEntity, text: string, yOffset_ptr: *float, is_subheader: bool = false) #foreign {}
_mp_rt_create_string_entry :: (dialog: *SettingsDialogEntity, label_text: string, initial_value: string, yOffset_ptr: *float, callback_proc: (string, *void) -> void, target_field_ptr_raw: *void) #foreign {}
_mp_rt_create_s64_entry    :: (dialog: *SettingsDialogEntity, label_text: string, initial_value: s64,    yOffset_ptr: *float, callback_proc: (string, *void) -> void, target_field_ptr_raw: *void) #foreign {}
_mp_rt_create_float_entry  :: (dialog: *SettingsDialogEntity, label_text: string, initial_value: float,  yOffset_ptr: *float, callback_proc: (string, *void) -> void, target_field_ptr_raw: *void, is_vec_component: bool = false) #foreign {}
// _mp_rt_create_bool_entry   :: (dialog: *SettingsDialogEntity, label_text: string, initial_value: bool,   yOffset_ptr: *float, callback_proc: (string, *void) -> void, target_field_ptr_raw: *void) #foreign {} // Removed
_mp_rt_create_bool_toggle_button :: (dialog: *SettingsDialogEntity, label_text: string, initial_value: bool, yOffset_ptr: *float, callback_proc: (bool, *void) -> void, target_field_ptr_raw: *void) #foreign {} 
_mp_rt_create_enum_entry   :: (dialog: *SettingsDialogEntity, label_text: string, initial_value_str: string, yOffset_ptr: *float, callback_proc: (string, *void) -> void, target_field_ptr_raw: *void, enum_name: string) #foreign {}
_mp_rt_add_array_placeholder_entry :: (dialog: *SettingsDialogEntity, label_text: string, yOffset_ptr: *float) #foreign {}

// Stubs for runtime parsing/conversion helpers 
// parse_bool_runtime :: (text: string) -> bool, bool #foreign {} // Removed
string_to_mouse_button_runtime :: (s: string) -> Crater.MouseButton #foreign {}
string_to_comment_style_runtime :: (s: string) -> CommentStyle #foreign {}
key_to_display_string_runtime :: (key: Crater.Key) -> string #foreign { return ""; }
display_string_to_key_runtime :: (s: string) -> Crater.Key #foreign {}
mouse_button_to_string_runtime :: (mb: Crater.MouseButton) -> string #foreign { return ""; }
comment_style_to_string_runtime :: (style: CommentStyle) -> string #foreign { return ""; }
unknown_enum_to_string_runtime :: (val_s64: s64) -> string #foreign { return "Unknown Enum"; }


#run {
    Basic.print("--- METAPROGRAM: Starting code generation ---\n");
    generated_code_output := generate_all_settings_sections_code(""); 
    Basic.print("--- METAPROGRAM: Generated Code Output ---\n%\n--- METAPROGRAM: End Code Output ---\n", generated_code_output);
}
```
