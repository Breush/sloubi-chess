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
    moves : struct {
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
    config.moves.mainColor = _read_vec3(json["moves"]["mainColor"]);
    config.moves.selectedColor = _read_vec3(json["moves"]["selectedColor"]);
    config.moves.selectedCommentColor = _read_vec3(json["moves"]["selectedCommentColor"]);
    config.moves.comments.shortStyle = _read_comment_style(json["moves"]["comments"]["shortStyle"]);
    config.moves.comments.normalStyle = _read_comment_style(json["moves"]["comments"]["normalStyle"]);
    config.moves.comments.longStyle = _read_comment_style(json["moves"]["comments"]["longStyle"]);
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

_read_comment_style :: (json : Chamber.JsonValue) -> CommentStyle {
    if json.str == "Inline" then return .Inline;
    if json.str == "Half" then return .Half;
    if json.str == "Full" then return .Full;
    if json.str == "SidedFull" then return .SidedFull;
    return .None;
}

#import "Chamber"; // For operator[] of JSON parser.
