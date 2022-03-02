Config :: struct {
    version : s64;
    background : struct {
        color : Chamber.vec3;
    }
    board : struct {
        pieces : string;
        lightSquareColor : Chamber.vec3;
        darkSquareColor : Chamber.vec3;
    }
    controls : struct {
        nextPly : Crater.Key;
        previousPly : Crater.Key;
        firstPly : Crater.Key;
        lastPly : Crater.Key;
        nextVariation : Crater.Key;
        previousVariation : Crater.Key;
    }
    moves : struct {
        fontFamily : string;
        fontSize : s64;
        mainColor : Chamber.vec3;
        selectedColor : Chamber.vec3;
        selectedCommentColor : Chamber.vec3;
        comments : struct {
            shortStyle : CommentStyle;
            normalStyle : CommentStyle;
            longStyle : CommentStyle;
            fullStyleWidth : float;
        }
    }
}

config_init :: (config : *Config, filename : string) {
    json, ok := Chamber.json_parse_file(filename);
    if !ok then Basic.log("Unable to read config file '%'.", filename, flags = .ERROR);

    // @todo Metaprog to fill the struct based on its content
    config.version = cast(s64) json["version"].number;
    config.background.color = _read_vec3(json["background"]["color"]);
    config.board.pieces = json["board"]["pieces"].str;
    config.board.lightSquareColor = _read_vec3(json["board"]["lightSquareColor"]);
    config.board.darkSquareColor = _read_vec3(json["board"]["darkSquareColor"]);
    config.controls.nextPly = _read_enum(json["controls"]["nextPly"], Crater.Key);
    config.controls.previousPly = _read_enum(json["controls"]["previousPly"], Crater.Key);
    config.controls.firstPly = _read_enum(json["controls"]["firstPly"], Crater.Key);
    config.controls.lastPly = _read_enum(json["controls"]["lastPly"], Crater.Key);
    config.controls.nextVariation = _read_enum(json["controls"]["nextVariation"], Crater.Key);
    config.controls.previousVariation = _read_enum(json["controls"]["previousVariation"], Crater.Key);
    config.moves.fontFamily = json["moves"]["fontFamily"].str;
    config.moves.fontSize = cast(s64) json["moves"]["fontSize"].number;
    config.moves.mainColor = _read_vec3(json["moves"]["mainColor"]);
    config.moves.selectedColor = _read_vec3(json["moves"]["selectedColor"]);
    config.moves.selectedCommentColor = _read_vec3(json["moves"]["selectedCommentColor"]);
    config.moves.comments.shortStyle = _read_enum(json["moves"]["comments"]["shortStyle"], CommentStyle);
    config.moves.comments.normalStyle = _read_enum(json["moves"]["comments"]["normalStyle"], CommentStyle);
    config.moves.comments.longStyle = _read_enum(json["moves"]["comments"]["longStyle"], CommentStyle);
    config.moves.comments.fullStyleWidth = cast(float) json["moves"]["comments"]["fullStyleWidth"].number;
}

#scope_file

_read_vec3 :: (json : Chamber.JsonValue) -> Chamber.vec3 {
    value : Chamber.vec3;
    value.x = cast(float) json[0].number;
    value.y = cast(float) json[1].number;
    value.z = cast(float) json[2].number;
    return value;
}

_read_enum :: (json : Chamber.JsonValue, $T : Type) -> T {
    typeInfo := type_info(T);
    for name, index : typeInfo.names {
        if name == json.str {
            return cast(T) typeInfo.values[index];
        }
    }
    Basic.log("Invalid value '%' for enum '%'.", json.str, T, flags = .ERROR);
    return cast(T) 0;
}

#import "Chamber"; // For operator[] of JSON parser.
