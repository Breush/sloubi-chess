// Config is user-configurable data.
// Persistence is application-dependent data, saved by user.

Config :: struct {
    version : s64;
    env : struct {
        backgroundColor : Chamber.vec3;
        contrastColor : Chamber.vec3;
        hoverColor : Chamber.vec3;
        textColor : Chamber.vec3;
        fontFamily : string;
        monoFontFamily : string;
        fontSize : s64;
        piecesSymbols : [..]string;
        piecesMap : [..]Crater.Key;
    }
    analysis : struct {
        externalSite : string;
        uciEngine: string;
        highlightColor : Chamber.vec4;
    }
    board : struct {
        pieces : string;
        lightSquareColor : Chamber.vec3;
        darkSquareColor : Chamber.vec3;
        highlightColors : struct {
            blue : Chamber.vec4;
            green : Chamber.vec4;
            red : Chamber.vec4;
            yellow : Chamber.vec4;
        }
        promotionSelecterColor : Chamber.vec4;
        highlightValidSquares : bool;
        showCapturedPiece : bool;
        dragAndDropMove : struct {
            enabled : bool;
            ghostOpacity : float;
        }
        clickClickMove : struct {
            enabled : bool;
        }
        destinationSquareMove : struct {
            enabled : bool;
            disambiguateWithLastMovedPiece : bool;
            mouseButton : Crater.MouseButton;
        }
        keyboardMove : struct {
            enabled : bool;
            numbersMap : [..]Crater.Key;
            selectNext : [..]Crater.Key;
            playSelected : [..]Crater.Key;
        }
    }
    controls : struct {
        undo : Crater.Key;
        nextPly : Crater.Key;
        previousPly : Crater.Key;
        firstPly : Crater.Key;
        lastPly : Crater.Key;
        editPlyComment : Crater.Key;
        deletePly : Crater.Key;
        nextVariation : Crater.Key;
        previousVariation : Crater.Key;
    }
    library : struct {
        path : string;
        gameTitleFormat : string;
    }
    moves : struct {
        mainColor : Chamber.vec3;
        interestingColor : Chamber.vec3;
        goodColor : Chamber.vec3;
        brillantColor : Chamber.vec3;
        dubiousColor : Chamber.vec3;
        mistakeColor : Chamber.vec3;
        blunderColor : Chamber.vec3;
        selectedColor : Chamber.vec3;
        selectedCommentColor : Chamber.vec3;
        variationsCollapsed : bool;
        compactThreshold : s64;
        comments : struct {
            shortStyle : CommentStyle;
            normalStyle : CommentStyle;
            longStyle : CommentStyle;
            fullStyleWidth : float;
        }
    }
}

Persistence :: struct {
    version : s64;
    fileSelect : struct {
        lastPath : string;
    }
}

config_cleanup :: (config : *Config) {
    Basic.free(config.env.fontFamily);
    Basic.free(config.env.monoFontFamily);
    for config.env.piecesSymbols { Basic.free(it); }
    Basic.array_free(config.env.piecesSymbols);
    Basic.array_free(config.env.piecesMap);
    Basic.free(config.analysis.externalSite);
    Basic.free(config.board.pieces);
    Basic.array_free(config.board.keyboardMove.numbersMap);
    Basic.array_free(config.board.keyboardMove.selectNext);
    Basic.array_free(config.board.keyboardMove.playSelected);
    Basic.free(config.library.path);
    Basic.free(config.library.gameTitleFormat);
}

persistence_cleanup :: (persistence : *Persistence) {
    Basic.free(persistence.fileSelect.lastPath);
}

// @todo Move to Chamber
read_json_as :: (data : *$T, filename : string, silentOnError := false) -> bool {
    json, ok := Chamber.json_parse_file(filename);
    if !ok {
        if !silentOnError then Basic.log_error("Unable to read file '%'.", filename);
        return false;
    }

    defer Chamber.json_free(json);

    read_json(cast(*u8) data, type_info(T), json);
    return true;
}

read_json :: (dataBytes : *u8, typeInfo : *Type_Info, json : Chamber.JsonValue) {
    if typeInfo.type == .INTEGER {
        targetTypeInfo := cast(*Type_Info_Integer) typeInfo;
        Basic.assert(targetTypeInfo.runtime_size == 8);
        Basic.assert(targetTypeInfo.signed);
        << cast(*s64) dataBytes = cast(s64) json.number;
    } else if typeInfo.type == .FLOAT {
        targetTypeInfo := cast(*Type_Info_Float) typeInfo;
        Basic.assert(targetTypeInfo.runtime_size == 4);
        << cast(*float) dataBytes = cast(float) json.number;
    } else if typeInfo.type == .BOOL {
        << cast(*bool) dataBytes = json.boolean;
    } else if typeInfo.type == .STRING {
        << cast(*string) dataBytes = Basic.copy_string(json.str);
    }  else if typeInfo.type == .ENUM {
        read_json_enum(dataBytes, cast(*Type_Info_Enum) typeInfo, *json);
    } else if typeInfo.type == .STRUCT {
        read_json_struct(dataBytes, cast(*Type_Info_Struct) typeInfo, *json);
    } else if typeInfo.type == .ARRAY {
        read_json_array(dataBytes, cast(*Type_Info_Array) typeInfo, *json);
    } else {
        Basic.log_error("Unsupported type tag: %.", typeInfo.type);
        Basic.assert(false);
    }
}

read_json_struct :: (dataBytes : *u8, typeInfo : *Type_Info_Struct, json : Chamber.JsonValue) {
    // Special handling of known types.
    if typeInfo == type_info(Chamber.vec3) {
        dataFloats := cast(*float) dataBytes;
        dataFloats[0] = cast(float) json[0].number;
        dataFloats[1] = cast(float) json[1].number;
        dataFloats[2] = cast(float) json[2].number;
        return;
    } else if typeInfo == type_info(Chamber.vec4) {
        dataFloats := cast(*float) dataBytes;
        dataFloats[0] = cast(float) json[0].number;
        dataFloats[1] = cast(float) json[1].number;
        dataFloats[2] = cast(float) json[2].number;
        dataFloats[3] = cast(float) json[3].number;
        return;
    }

    for member : typeInfo.members {
        jsonValue := Chamber.get(json, member.name);
        if jsonValue.type == .INVALID {
            // The JSON is missing one of the members. Just ignore it.
            continue;
        }
        read_json(dataBytes + member.offset_in_bytes, member.type, jsonValue);
    }
}

read_json_enum :: (dataBytes : *u8, typeInfo : *Type_Info_Enum, json : Chamber.JsonValue) {
    Basic.assert(typeInfo.internal_type.runtime_size == 8);
    for name, index : typeInfo.names {
        if name == json.str {
            << cast(*s64) (cast(*u8) dataBytes ) = typeInfo.values[index];
            return;
        }
    }
    Basic.log_error("Invalid value '%' for enum '%'.", json.str, typeInfo.name);
}

read_json_array :: (dataBytes : *u8, typeInfo : *Type_Info_Array, json : Chamber.JsonValue) {
    if typeInfo.array_type == .RESIZABLE {
        targetArray := cast(*[..]u8) dataBytes;
        elementSize := typeInfo.element_type.runtime_size;
        Basic.array_resize(targetArray, json.array.count * elementSize);

        for element, elementIndex : json.array {
            read_json(targetArray.data + elementIndex * elementSize, typeInfo.element_type, element);
        }

        targetArray.count = json.array.count;
    } else {
        Basic.log_error("Unsupported array type: %.", typeInfo.array_type);
        Basic.assert(false);
    }
}

#scope_file

operator[] :: Chamber.operator[];

//
// JSON Writing Implementation
//

// Enum to String Helpers for JSON serialization
// These should produce the exact string values expected in config.json

// For Crater.Key, the settings dialog uses integer representation for now.
// For JSON, it's often preferred to use string names if the schema expects them.
// Assuming the config.json expects string names for keys (e.g., "Escape", "F1").
// If Crater.key_to_name exists and is suitable, it should be used.
// Otherwise, a manual mapping or integer-as-string might be necessary.
// For now, let's assume key_to_display_string from settings_dialog is what we need,
// or we create a specific one here if format differs.
// Let's use a simple integer-to-string conversion for now, matching the current dialog behavior.
// If the actual config.json requires string names like "Escape", this needs to be more elaborate.
key_to_config_string :: (key: Crater.Key) -> string {
    // Ideal: return Crater.key_to_name(key);
    return Basic.tprint("%", cast(s32) key); // Matching current dialog practice
}

mouse_button_to_config_string :: (mb: Crater.MouseButton) -> string {
    if mb == .Left return "Left";
    if mb == .Right return "Right";
    if mb == .Middle return "Middle";
    if mb == .X1 return "X1";
    if mb == .X2 return "X2";
    return "Unknown"; // Should match what read_json_enum expects for Crater.MouseButton if it's custom handled
}

comment_style_to_config_string :: (style: CommentStyle) -> string {
    // These must match the string values used in the JSON file (and thus by read_json_enum)
    if style == .Inline then return "Inline";
    if style == .Half then return "Half";
    if style == .Full then return "Full";
    if style == .SidedFull then return "SidedFull";
    return "Inline"; // Default or error
}


json_from_s64 :: (val: s64) -> Chamber.JsonValue {
    return Chamber.make_number(cast(float64) val);
}

json_from_float :: (val: float) -> Chamber.JsonValue {
    return Chamber.make_number(cast(float64) val);
}

json_from_bool :: (val: bool) -> Chamber.JsonValue {
    return Chamber.make_boolean(val);
}

json_from_string :: (val: string) -> Chamber.JsonValue {
    if val == null return Chamber.make_null(); // Or make_string("")
    return Chamber.make_string(val);
}

json_from_vec3 :: (val: Chamber.vec3) -> Chamber.JsonValue {
    arr := Chamber.make_array(3);
    Chamber.array_add(arr, json_from_float(val.x));
    Chamber.array_add(arr, json_from_float(val.y));
    Chamber.array_add(arr, json_from_float(val.z));
    return arr;
}

json_from_vec4 :: (val: Chamber.vec4) -> Chamber.JsonValue {
    arr := Chamber.make_array(4);
    Chamber.array_add(arr, json_from_float(val.x));
    Chamber.array_add(arr, json_from_float(val.y));
    Chamber.array_add(arr, json_from_float(val.z));
    Chamber.array_add(arr, json_from_float(val.w));
    return arr;
}

// Forward declarations for mutually recursive functions
json_from_struct :: (data_ptr: *void, type_info_struct: *Type_Info_Struct) -> Chamber.JsonValue #modify { /* Placeholder */ return Chamber.make_null(); }
json_from_array :: (data_ptr: *void, type_info_array: *Type_Info_Array) -> Chamber.JsonValue #modify { /* Placeholder */ return Chamber.make_null(); }
json_from_type :: (data_ptr: *void, type_info_val: *Type_Info) -> Chamber.JsonValue #modify { /* Placeholder */ return Chamber.make_null(); }

json_from_enum :: (data_ptr: *void, type_info_enum: *Type_Info_Enum) -> Chamber.JsonValue {
    // This needs to map enum value to its string representation as defined in the JSON schema.
    // The read_json_enum iterates type_info_enum.names and type_info_enum.values.
    // We need to find the string name corresponding to the current enum value.
    
    current_value := << cast(*s64) data_ptr; // Assuming enums are s64 internally based on read_json_enum

    // Specific handlers based on enum type_info, as generic mapping from value to name is hard.
    if type_info_enum == type_info(Crater.MouseButton) {
        mb_val := << cast(*Crater.MouseButton) data_ptr;
        return json_from_string(mouse_button_to_config_string(mb_val));
    } else if type_info_enum == type_info(CommentStyle) {
        cs_val := << cast(*CommentStyle) data_ptr;
        return json_from_string(comment_style_to_config_string(cs_val));
    } else if type_info_enum == type_info(Crater.Key) { 
        // This is tricky because Crater.Key is a large enum.
        // read_json_enum for Crater.Key is not shown, but it would map strings to key values.
        // For writing, we'd ideally use Crater.key_to_name or similar.
        // As a fallback, writing the integer value as a string.
        key_val := << cast(*Crater.Key) data_ptr;
        return json_from_string(key_to_config_string(key_val));
    }

    // Generic fallback: try to find the name by value. This is inefficient.
    for i: 0..type_info_enum.values.count-1 {
        if type_info_enum.values[i] == current_value {
            return json_from_string(type_info_enum.names[i]);
        }
    }
    
    Basic.log_error("Could not find string representation for enum value % of type %", current_value, type_info_enum.name);
    return Chamber.make_string("UNKNOWN_ENUM_VALUE");
}

#modify json_from_array :: (data_ptr: *void, type_info_array: *Type_Info_Array) -> Chamber.JsonValue {
    arr_json := Chamber.make_array();
    
    if type_info_array.array_type == .RESIZABLE {
        dyn_array_header := cast(*Basic.Array_Header) data_ptr;
        item_ptr := dyn_array_header.data;
        element_size := type_info_array.element_type.runtime_size;

        for i: 0..dyn_array_header.count-1 {
            element_json := json_from_type(item_ptr, type_info_array.element_type);
            Chamber.array_add(arr_json, element_json);
            item_ptr = item_ptr + element_size;
        }
    } else {
        Basic.log_error("Unsupported array type for JSON writing: %", type_info_array.array_type);
        // Handle other array types if necessary (e.g., fixed-size)
    }
    return arr_json;
}

#modify json_from_struct :: (data_ptr: *void, type_info_struct: *Type_Info_Struct) -> Chamber.JsonValue {
    // Special handling for known types that are structs but have custom JSON representations (like arrays)
    if type_info_struct == type_info(Chamber.vec3) {
        return json_from_vec3(<<cast(*Chamber.vec3) data_ptr);
    } else if type_info_struct == type_info(Chamber.vec4) {
        return json_from_vec4(<<cast(*Chamber.vec4) data_ptr);
    }

    obj_json := Chamber.make_object();
    for member: type_info_struct.members {
        member_data_ptr := cast(*u8)data_ptr + member.offset_in_bytes;
        member_json_value := json_from_type(member_data_ptr, member.type);
        Chamber.object_add(obj_json, member.name, member_json_value);
    }
    return obj_json;
}

#modify json_from_type :: (data_ptr: *void, type_info_val: *Type_Info) -> Chamber.JsonValue {
    if type_info_val.type == {
    case .INTEGER;
        // Assuming s64 based on Config struct and read_json
        return json_from_s64(<<cast(*s64) data_ptr);
    case .FLOAT;
        // Assuming float32 based on Config struct (e.g. ghostOpacity)
        return json_from_float(<<cast(*float) data_ptr);
    case .BOOL;
        return json_from_bool(<<cast(*bool) data_ptr);
    case .STRING;
        return json_from_string(<<cast(*string) data_ptr);
    case .ENUM;
        return json_from_enum(data_ptr, cast(*Type_Info_Enum) type_info_val);
    case .STRUCT;
        return json_from_struct(data_ptr, cast(*Type_Info_Struct) type_info_val);
    case .ARRAY;
        return json_from_array(data_ptr, cast(*Type_Info_Array) type_info_val);
    // case .POINTER; // Might need handling if config contains pointers (should not for simple data config)
    // case .FUNCTION; // Not applicable for data
    // case .VOID; // Not applicable
    // case .TYPE; // Not applicable
    else;
        Basic.log_error("JSON serialization not implemented for type: %", type_info_val.type);
        return Chamber.make_null();
    }
}

write_json_as :: (data: *$T, filename: string) -> bool {
    root_json_value := json_from_type(cast(*void) data, type_info(T));
    if root_json_value.type == .INVALID || root_json_value.type == .NULL { // Check if root conversion failed
        Basic.log_error("Failed to convert data to JSON for file '%'.", filename);
        if root_json_value.type != .INVALID Chamber.json_free(root_json_value); // Free if it's just Null but valid
        return false;
    }

    success := Chamber.json_write_file(root_json_value, filename, .Indented);
    Chamber.json_free(root_json_value);

    if !success {
        Basic.log_error("Failed to write JSON to file '%'.", filename);
    }
    return success;
}
