skip_bom :: inline (bytes : *string) {
    // UTF-8
    if bytes.*[0] == 0xEF && bytes.*[1] == 0xBB && bytes.*[2] == 0xBF {
        Basic.advance(bytes, 3);
    }
}

skip_blanks :: inline (bytes : *string) {
    while bytes.count > 0 &&
          (bytes.*[0] == #char " " || bytes.*[0] == #char "\t" ||
           bytes.*[0] == #char "\r" || bytes.*[0] == #char "\n") {
        Basic.advance(bytes);
    }
}

skip_until :: inline (bytes : *string, sentinel : u8) {
    c := bytes.*[0];
    while c != sentinel {
        Basic.advance(bytes);
        if bytes.count == 0 then return;
        c = bytes.*[0];
    }
    Basic.advance(bytes);
}

parse_word :: inline (bytes : *string) -> string {
    return parse_until(bytes, .[#char " ", #char "\n"]);
}

parse_until :: inline (bytes : *string, characters : []u8) -> string {
    word : string;
    word.data = bytes.data;

    while true {
        for character : characters {
            if bytes.*[0] == character then return word;
        }

        word.count += 1;
        Basic.advance(bytes);
    }

    return word;
}
