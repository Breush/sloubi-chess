// Config is user-configurable data.
// Persistence is application-dependent data, saved by user.

Config :: struct {
    version : s64;
    env : struct {
        backgroundColor : Chamber.vec3;
        secondaryBackgroundColor : Chamber.vec3;
        selectionBackgroundColor : Chamber.vec3;
        textColor : Chamber.vec3;
        fontFamily : string;
        monoFontFamily : string;
        fontSize : s64;
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
        pieceAsSymbol : bool;
        variationsCollapsed : bool;
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

// @todo Move to Chamber
readJsonAs :: (data : *$T, filename : string, silentOnError := false) -> bool {
    typeInfo := type_info(T);
    _CHECK(typeInfo.type == .STRUCT, "Type is not a struct.");

    json, ok := Chamber.json_parse_file(filename);
    if !ok {
        if !silentOnError then Basic.log_error("Unable to read file '%'.", filename);
        return false;
    }

    defer Chamber.json_free(json);
    readJsonStruct(cast(*u8) data, typeInfo, json);
    return true;
}

readJsonStruct :: (dataBytes : *u8, typeInfo : *Type_Info_Struct, json : Chamber.JsonValue) {
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
        memberDataBytes := dataBytes + member.offset_in_bytes;

        if member.type.type == .INTEGER {
            memberType := cast(*Type_Info_Integer) member.type;
            Basic.assert(memberType.runtime_size == 8);
            Basic.assert(memberType.signed);
            << cast(*s64) memberDataBytes = cast(s64) json[member.name].number;
        } else if member.type.type == .FLOAT {
            memberType := cast(*Type_Info_Float) member.type;
            Basic.assert(memberType.runtime_size == 4);
            << cast(*float) memberDataBytes = cast(float) json[member.name].number;
        } else if member.type.type == .BOOL {
            << cast(*bool) memberDataBytes = json[member.name].boolean;
        } else if member.type.type == .STRING {
            << cast(*string) memberDataBytes = Basic.copy_string(json[member.name].str);
        }  else if member.type.type == .ENUM {
            readJsonEnum(memberDataBytes, cast(*Type_Info_Enum) member.type, *json[member.name]);
        } else if member.type.type == .STRUCT {
            readJsonStruct(memberDataBytes, cast(*Type_Info_Struct) member.type, *json[member.name]);
        } else {
            Basic.log_error("Unsupported type tag: %.", member.type.type);
            Basic.assert(false);
        }
    }
}

readJsonEnum :: (dataBytes : *u8, typeInfo : *Type_Info_Enum, json : Chamber.JsonValue) {
    Basic.assert(typeInfo.internal_type.runtime_size == 8);
    for name, index : typeInfo.names {
        if name == json.str {
            << cast(*s64) (cast(*u8) dataBytes ) = typeInfo.values[index];
            return;
        }
    }
    Basic.log_error("Invalid value '%' for enum '%'.", json.str, typeInfo.name);
}

#scope_file

#import "Chamber"; // For operator[] of JSON parser.
