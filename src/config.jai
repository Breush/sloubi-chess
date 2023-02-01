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
    }
    analysis : struct {
        externalSite : string;
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
            piecesMap : [..]Crater.Key;
            numbersMap : [..]Crater.Key;
            selectNext : [..]Crater.Key;
            playSelected : [..]Crater.Key;
        }
    }
    controls : struct {
        nextPly : Crater.Key;
        previousPly : Crater.Key;
        firstPly : Crater.Key;
        lastPly : Crater.Key;
        editPlyComment : Crater.Key;
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
    Basic.free(config.analysis.externalSite);
    Basic.free(config.board.pieces);
    Basic.array_free(config.board.keyboardMove.piecesMap);
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
        jsonValue := json[member.name];
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

#import "Chamber"; // For operator[] of JSON parser.
