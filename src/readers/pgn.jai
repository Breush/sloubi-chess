
load_pgn :: (filename : string) -> bool {
    fileBytes, readOk := File.read_entire_file(filename);
    Chamber._CHECK(readOk, Basic.tprint("Unable to read PGN file: %", filename)); // @todo Hard quitting is probably a bad idea.
    defer Basic.free(fileBytes);

    game := *instance.game; // Filling the global game for now.
    rootNode := game_add_variation_node(game, *game.mainVariation);
    rootNode.position = get_starting_position();

    // Parsing tags
    bytes := fileBytes;
    _skip_blanks(*bytes);

    while bytes[0] == #char "[" {
        Basic.advance(*bytes);
        tagName := _parse_word(*bytes);
        Basic.advance(*bytes);
        Basic.advance(*bytes); // Skipping the quote.

        if tagName == "FEN" {
            rootNode.position = load_fen(bytes);
        } else if tagName == "BoardOrientation" {
            game.boardOrientation = ifx bytes[0] == #char "W" then Color.White else Color.Black;
        } else {
            Basic.log("Ignored tag '%'...", tagName, flags = .WARNING);
        }

        _skip_to_end_of_tag(*bytes);
        _skip_blanks(*bytes);
    }

    // Parsing main variation (and therefore its subvariations)
    _parse_variation(*bytes, *game.mainVariation);
    _skip_blanks(*bytes);

    Chamber._CHECK(bytes.count == 0, Basic.tprint("Leftovers: %", bytes));

    return true;
}

#scope_file

// Based on https://en.wikipedia.org/wiki/Numeric_Annotation_Glyphs
Nag :: enum {
    None :: 0;
    Good :: 1; // !
    Mistake :: 2; // ?
    Brillant :: 3; // !!
    Blunder :: 4; // ??
    Interesting :: 5; // !?
    Dubious :: 6; // ?!
    Forced :: 7; // □
    Singular :: 8;
    Worst :: 9;

    Drawish :: 10; // =
    EqualQuiet :: 11;
    EqualActive :: 12;
    Unclear :: 13; // ∞

    WhiteSlightAdvantage :: 14; // ⩲
    BlackSlightAdvantage :: 15; // ⩱
    WhiteModerateAdvantage :: 16; // ±
    BlackModerateAdvantage :: 17; // ∓
    WhiteDecisiveAdvantage :: 18; // +-
    BlackDecisiveAdvantage :: 19; // -+
    WhiteCrushingAdvantage :: 20;
    BlackCrushingAdvantage :: 21;

    WhiteZugzwang :: 22; // ⨀
    BlackZugzwang :: 23; // ⨀

    WhiteSlightSpaceAdvantage :: 24;
    BlackSlightSpaceAdvantage :: 25;
    WhiteModerateSpaceAdvantage :: 26; // ○
    BlackModerateSpaceAdvantage :: 27; // ○
    WhiteDecisiveSpaceAdvantage :: 28;
    BlackDecisiveSpaceAdvantage :: 29;

    WhiteSlightTimeAdvantage :: 30;
    BlackSlightTimeAdvantage :: 31;
    WhiteModerateTimeAdvantage :: 32; // ↻
    BlackModerateTimeAdvantage :: 33; // ↻
    WhiteDecisiveTimeAdvantage :: 34;
    BlackDecisiveTimeAdvantage :: 35;

    WhiteInitiative :: 36; // ↑
    BlackInitiative :: 37; // ↑
    WhiteLastingInitiative :: 38;
    BlackLastingInitiative :: 39;

    WhiteAttack :: 40; // →
    BlackAttack :: 41; // →

    WhiteInsufficientCompensation :: 42;
    BlackInsufficientCompensation :: 43;
    WhiteSufficientCompensation :: 44; // =∞
    BlackSufficientCompensation :: 45; // =∞
    WhiteEffectiveCompensation :: 46;
    BlackEffectiveCompensation :: 47;

    // 48 to 129 are not really interesting.

    WhiteSlightCounterplay :: 130;
    BlackSlightCounterplay :: 131;
    WhiteModerateCounterplay :: 132; // ⇆
    BlackModerateCounterplay :: 133; // ⇆
    WhiteDecisiveCounterplay :: 134;
    BlackDecisiveCounterplay :: 135;

    WhiteModerateTimeControlPressure :: 136;
    BlackModerateTimeControlPressure :: 137;
    WhiteSevereTimeControlPressure :: 138; // ⨁
    BlackSevereTimeControlPressure :: 139; // ⨁

    // 140+ are non-standard. I keep here those used by lichess.

    WithIdea :: 140; // ∆
    Novelty :: 146; // ℕ
}

_nag_to_move_annotation :: (nag : Nag) -> MoveAnnotation {
    if nag == {
        case .None; return .None;
        case .Good; return .Good;
        case .Mistake; return .Mistake;
        case .Brillant; return .Brillant;
        case .Blunder; return .Blunder;
        case .Interesting; return .Interesting;
        case .Dubious; return .Dubious;
        case .Forced; return .Forced;
        case .WhiteZugzwang; return .Zugzwang;
        case .BlackZugzwang; return .Zugzwang;
    }
    return .None;
}

_nag_to_position_annotation :: (nag : Nag) -> PositionAnnotation {
    if nag == {
        case .None; return .None;
        case .Drawish; return .Drawish;
        case .Unclear; return .Unclear;
        case .WhiteSlightAdvantage; return .WhiteSlightAdvantage;
        case .BlackSlightAdvantage; return .BlackSlightAdvantage;
        case .WhiteModerateAdvantage; return .WhiteModerateAdvantage;
        case .BlackModerateAdvantage; return .BlackModerateAdvantage;
        case .WhiteDecisiveAdvantage; return .WhiteDecisiveAdvantage;
        case .BlackDecisiveAdvantage; return .BlackDecisiveAdvantage;
        case .WhiteCrushingAdvantage; return .WhiteDecisiveAdvantage;
        case .BlackCrushingAdvantage; return .BlackDecisiveAdvantage;
    }
    return .None;
}

_nag_to_observation_annotation :: (nag : Nag) -> ObservationAnnotation {
    if nag == {
        case .None; return .None;
        case .WhiteSlightSpaceAdvantage; return .SpaceAdvantage;
        case .BlackSlightSpaceAdvantage; return .SpaceAdvantage;
        case .WhiteModerateSpaceAdvantage; return .SpaceAdvantage;
        case .BlackModerateSpaceAdvantage; return .SpaceAdvantage;
        case .WhiteDecisiveSpaceAdvantage; return .SpaceAdvantage;
        case .BlackDecisiveSpaceAdvantage; return .SpaceAdvantage;
        case .WhiteSlightTimeAdvantage; return .TimeAdvantage;
        case .BlackSlightTimeAdvantage; return .TimeAdvantage;
        case .WhiteModerateTimeAdvantage; return .TimeAdvantage;
        case .BlackModerateTimeAdvantage; return .TimeAdvantage;
        case .WhiteDecisiveTimeAdvantage; return .TimeAdvantage;
        case .BlackDecisiveTimeAdvantage; return .TimeAdvantage;
        case .WhiteInitiative; return .Initiative;
        case .BlackInitiative; return .Initiative;
        case .WhiteLastingInitiative; return .Initiative;
        case .BlackLastingInitiative; return .Initiative;
        case .WhiteAttack; return .Attack;
        case .BlackAttack; return .Attack;
        case .WhiteSufficientCompensation; return .Compensation;
        case .BlackSufficientCompensation; return .Compensation;
        case .WhiteEffectiveCompensation; return .Compensation;
        case .BlackEffectiveCompensation; return .Compensation;
        case .WhiteSlightCounterplay; return .Counterplay;
        case .BlackSlightCounterplay; return .Counterplay;
        case .WhiteModerateCounterplay; return .Counterplay;
        case .BlackModerateCounterplay; return .Counterplay;
        case .WhiteDecisiveCounterplay; return .Counterplay;
        case .BlackDecisiveCounterplay; return .Counterplay;
        case .WhiteModerateTimeControlPressure; return .TimeControlPressure;
        case .BlackModerateTimeControlPressure; return .TimeControlPressure;
        case .WhiteSevereTimeControlPressure; return .TimeControlPressure;
        case .BlackSevereTimeControlPressure; return .TimeControlPressure;
        case .WithIdea; return .WithIdea;
        case .Novelty; return .Novelty;
    }
    return .None;
}

_skip_blanks :: (bytes : *string) {
    while bytes.count > 0 &&
          ((<<bytes)[0] == #char " " || (<<bytes)[0] == #char "\t" ||
           (<<bytes)[0] == #char "\r" || (<<bytes)[0] == #char "\n") {
        Basic.advance(bytes);
    }
}

_skip_to_end_of_tag :: (bytes : *string) {
    c := (<<bytes)[0];
    while c != #char "]" {
        Basic.advance(bytes);
        c = (<<bytes)[0];
    }
    Basic.advance(bytes);
}

_parse_move_number :: (bytes : *string) {
    while bytes.count > 0 &&
          (<<bytes)[0] != #char "." {
        if (<<bytes)[0] < #char "0" || (<<bytes)[0] > #char "9" {
            bytes.count = Basic.min(bytes.count, 10);
            Basic.log("Was expecting a move number here: %", <<bytes, flags=.ERROR);
        }

        Basic.advance(bytes);
    }

    while bytes.count > 0 && (<<bytes)[0] == #char "." {
        Basic.advance(bytes);
    }

    if bytes.count > 0 {
        Basic.advance(bytes);
    }

    _skip_blanks(bytes);
}

_parse_potential_move_number :: (bytes : *string) -> bool {
    if (<<bytes)[0] < #char "0" || (<<bytes)[0] > #char "9" {
        return false;
    }

    _parse_move_number(bytes);
    return true;
}

_parse_move :: (bytes : *string, variation : *Variation, color : Color) {
    lastPosition := Basic.peek(variation.nodes).position;
    lastPosition.annotation = .None;
    lastPosition.observationAnnotations.count = 0;
    lastPosition.lastMove = .{};

    capture : bool;
    sourceCoord, targetCoord : Coord = 0xFF, 0xFF;
    promotionPieceKind : PieceKind;

    piece : Piece;
    piece.color = color;

    // Pawn move
    if (<<bytes)[0] >= #char "a" && (<<bytes)[0] <= #char "h" {
        piece.kind = .Pawn;

        sourceHintCoord : Coord = 0xFF;
        sourceHintCoord, targetCoord, capture = _parse_pgn_move(bytes);

        coord_copy_row(*sourceHintCoord, targetCoord);
        if !capture {
            coord_copy_col(*sourceHintCoord, targetCoord);
        }

        // Find the source square of the piece
        rowDirection := ifx color == .White then cast(s8) -1 else cast(s8) 1;
        sourceCoord = position_find_piece_in_direction(lastPosition, piece, 0xFF, sourceHintCoord, rowDirection, 0 , 2);

        // Checking for promotion
        promotionPieceKind = _parse_potential_promotion(bytes);
    }
    // Castling
    else if (<<bytes)[0] == #char "O" {
        piece.kind = .King;

        _parse_expected(bytes, #char "O");
        _parse_expected(bytes, #char "-");
        _parse_expected(bytes, #char "O");

        longCastling := _parse_potential_expected(bytes, #char "-");
        if longCastling {
            _parse_expected(bytes, #char "O");
        }

        row := ifx color == .White then cast(u8) 0 else cast(u8) 7;
        sourceCoord = coord(row, 4);
        targetCoord = coord(row, ifx longCastling then cast(u8) 2 else cast(u8) 6);
    }
    // Piece move
    else {
        piece.kind = _parse_piece_kind(bytes);

        sourceHintCoord : Coord = 0xFF;
        sourceHintCoord, targetCoord, capture = _parse_pgn_move(bytes);
        sourceCoord = position_find_piece_source(lastPosition, piece, sourceHintCoord, targetCoord);
    }

    // @todo :AutoCheck Should not be our job to update position with this info.
    lastPosition.check = _parse_potential_check(bytes);
    lastPosition.mate = _parse_potential_mate(bytes);
    _skip_blanks(bytes);

    // Updating the game
    if coord_is_valid(sourceCoord) {
        position_play_move(*lastPosition, sourceCoord, targetCoord, promotionPieceKind);

        node := game_add_variation_node(*instance.game, variation);
        node.position = lastPosition;
    }
}

_parse_potential_col :: (bytes : *string) -> u8 {
    if (<<bytes)[0] >= #char "a" && (<<bytes)[0] <= #char "h" {
        return _parse_col(bytes);
    }
    return 0xFF;
}

_parse_potential_row :: (bytes : *string) -> u8 {
    if (<<bytes)[0] >= #char "1" && (<<bytes)[0] <= #char "8" {
        return _parse_row(bytes);
    }
    return 0xFF;
}

_parse_potential_expected :: (bytes : *string, c : u8) -> bool {
    if (<<bytes)[0] == c {
        return _parse_expected(bytes, c);
    }
    return false;
}

_parse_expected :: (bytes : *string, c : u8) -> bool {
    Chamber._CHECK((<<bytes)[0] == c, Basic.tprint("Was expecting a '%' here: %", Basic.to_string(*c, 1), <<bytes));
    Basic.advance(bytes);
    return true;
}

_parse_col :: (bytes : *string) -> u8 {
    Chamber._CHECK((<<bytes)[0] >= #char "a" && (<<bytes)[0] <= #char "h", 0xFF, Basic.tprint("Was expecting a column here: %", <<bytes));
    col := (<<bytes)[0] - #char "a";
    Basic.advance(bytes);
    return col;
}

_parse_row :: (bytes : *string) -> u8 {
    Chamber._CHECK((<<bytes)[0] >= #char "1" && (<<bytes)[0] <= #char "8", 0xFF, Basic.tprint("Was expecting a row here: %", <<bytes));
    col := (<<bytes)[0] - #char "1";
    Basic.advance(bytes);
    return col;
}

_parse_potential_capture :: (bytes : *string) -> bool {
    if (<<bytes)[0] == #char "x" {
        Basic.advance(bytes);
        return true;
    }
    return false;
}

_parse_potential_check :: (bytes : *string) -> bool {
    if (<<bytes)[0] == #char "+" {
        Basic.advance(bytes);
        return true;
    }
    return false;
}

_parse_potential_mate :: (bytes : *string) -> bool {
    if (<<bytes)[0] == #char "#" {
        Basic.advance(bytes);
        return true;
    }
    return false;
}

_parse_potential_promotion :: (bytes : *string) -> PieceKind {
    if (<<bytes)[0] != #char "=" then return .Empty;
    Basic.advance(bytes);

    return _parse_piece_kind(bytes);
}

_parse_pgn_move :: (bytes : *string) -> (sourceHintCoord : Coord, targetCoord : Coord, capture : bool) {
    sourceHintCol := _parse_potential_col(bytes);
    sourceHintRow := _parse_potential_row(bytes);
    capture := _parse_potential_capture(bytes);
    targetCol := _parse_potential_col(bytes);
    if targetCol == 0xFF {
        targetCol = sourceHintCol;
        sourceHintCol = 0xFF;
    }
    targetRow := _parse_potential_row(bytes);
    if targetRow == 0xFF {
        targetRow = sourceHintRow;
        sourceHintRow = 0xFF;
    }

    return (coord(sourceHintRow, sourceHintCol), coord(targetRow, targetCol), capture);
}

_parse_piece_kind :: (bytes : *string) -> PieceKind {
    pieceKind := PieceKind.Empty;

    if      (<<bytes)[0] == #char "B" then pieceKind = .Bishop;
    else if (<<bytes)[0] == #char "K" then pieceKind = .King;
    else if (<<bytes)[0] == #char "N" then pieceKind = .Knight;
    else if (<<bytes)[0] == #char "Q" then pieceKind = .Queen;
    else if (<<bytes)[0] == #char "R" then pieceKind = .Rook;
    else {
        Basic.log("Unable to parse piece kind here: %", <<bytes, flags = .ERROR);
    }

    Basic.advance(bytes);
    return pieceKind;
}

// +1 White wins, -1 Black wins, 0 Draw
_parse_potential_result :: (bytes : *string) -> (bool, s8) {
    if (<<bytes)[0] == #char "1" {
        // Peeking
        if (<<bytes)[1] == #char "-" {
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "-");
            _parse_expected(bytes, #char "0");
            return true, 1;
        } else if (<<bytes)[1] == #char "/" {
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "/");
            _parse_expected(bytes, #char "2");
            _parse_expected(bytes, #char "-");
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "/");
            _parse_expected(bytes, #char "2");
            return true, 1;
        }
    } else if (<<bytes)[0] == #char "0" {
        _parse_expected(bytes, #char "0");
        _parse_expected(bytes, #char "-");
        _parse_expected(bytes, #char "1");
        return true, -1;
    } else if (<<bytes)[0] == #char "*" {
        _parse_expected(bytes, #char "*");
        return true, 0xFF; // Interrupted game
    }

    return false, 0xFF;
}

_parse_potential_comment :: (bytes : *string) -> (string, bool) {
    if (<<bytes)[0] != #char "{" then return ("", false);
    Basic.advance(bytes);
    _skip_blanks(bytes);

    sb : Basic.String_Builder;
    Basic.init_string_builder(*sb);

    whitespacesToTrim := 0;
    previousIsBackslash := false;
    while previousIsBackslash || (<<bytes)[0] != #char "}" {
        previousIsBackslash = !previousIsBackslash && (<<bytes)[0] == #char "\\";
        if (<<bytes)[0] == #char " " then whitespacesToTrim += 1;
        else whitespacesToTrim = 0;


        if (<<bytes)[0] == #char "\n" then Basic.append(*sb, #char " ");
        else if !previousIsBackslash {
            // Special command. @todo Detect arrows and circles!
            if (<<bytes)[0] == #char "[" && (<<bytes)[1] == #char "%" {
                while (<<bytes)[0] != #char "]" {
                    Basic.advance(bytes);
                }
            } else {
                Basic.append(*sb, (<<bytes)[0]);
            }
        }
        Basic.advance(bytes);

    }
    Basic.advance(bytes);
    _skip_blanks(bytes);

    str := Basic.builder_to_string(*sb);
    str.count -= whitespacesToTrim;
    return (str, true);
}

_parse_potential_comments :: (bytes : *string, variation : *Variation) {
    fullComment : string;

    while true {
        comment, ok := _parse_potential_comment(bytes);
        if !ok then break;

        if fullComment.count == 0 then fullComment = comment;
        else fullComment = Basic.sprint("%\n%", fullComment, comment);
    }

    Basic.peek(variation.nodes).comment = fullComment;
}

_parse_potential_variation :: (bytes : *string, parentVariation : *Variation, color : Color) -> bool {
    if (<<bytes)[0] != #char "(" then return false;
    Basic.advance(bytes);

    lastNode := Basic.peek(parentVariation.nodes);
    variation := game_add_variation(*instance.game, lastNode);

    node := game_add_variation_node(*instance.game, variation);
    node.position = parentVariation.nodes[parentVariation.nodes.count - 2].position;

    _parse_variation(bytes, variation, color);

    _skip_blanks(bytes);
    _parse_expected(bytes, #char ")");
    _skip_blanks(bytes);
    return true;
}

_parse_variation :: (bytes : *string, variation : *Variation, firstColor := Color.White) {
    _parse_potential_comments(bytes, variation);

    firstLoop := true;
    while bytes.count > 0 {
        if !firstLoop || firstColor == .White {
            while _parse_potential_variation(bytes, variation, .Black) {}
            if (<<bytes)[0] == #char ")" then break; // End of variation
            if !_parse_potential_annotated_move(bytes, variation, .White) then break;
        }

        while _parse_potential_variation(bytes, variation, .White) {}
        if (<<bytes)[0] == #char ")" then break;
        if !_parse_potential_annotated_move(bytes, variation, .Black) then break;

        firstLoop = false;
    }
}

_parse_potential_annotated_move :: (bytes : *string, variation : *Variation, color : Color) -> bool {
    // position_debug_dump(Basic.peek(variation.nodes).position);

    _parse_potential_move_number(bytes);
    _parse_move(bytes, variation, color);
    while _parse_potential_annotation(bytes, variation) {}
    _parse_potential_comments(bytes, variation);

    if (<<bytes)[0] == #char ")" then return false;
    if _parse_potential_result(bytes) then return false;

    return true;
}

// Ignoring NAG et al. for now
_parse_potential_annotation :: (bytes : *string, variation : *Variation) -> bool {
    nag : Nag;

    if (<<bytes)[0] == #char "$" {
        Basic.advance(bytes);
        ok : bool;
        nagValue : s64;
        nagValue, ok, (<<bytes) = Basic.to_integer(<<bytes);
        nag = cast(Nag) nagValue;
    }

    if (<<bytes)[0] == #char "!" {
        Basic.advance(bytes);
        if (<<bytes)[0] == #char "!" { nag = .Brillant; Basic.advance(bytes); }
        else if (<<bytes)[0] == #char "?" { nag == .Interesting; Basic.advance(bytes); }
        else nag = .Good;
    } else if (<<bytes)[0] == #char "?" {
        Basic.advance(bytes);
        if (<<bytes)[0] == #char "?" { nag = .Blunder; Basic.advance(bytes); }
        else if (<<bytes)[0] == #char "!" { nag == .Dubious; Basic.advance(bytes); }
        else nag = .Mistake;
    }

    _skip_blanks(bytes);

    if nag != .None {
        position := *Basic.peek(variation.nodes).position;
        moveAnnotation := _nag_to_move_annotation(nag);
        if moveAnnotation != .None {
            position.lastMove.annotation = moveAnnotation;
        }
        positionAnnotation := _nag_to_position_annotation(nag);
        if positionAnnotation != .None {
            position.annotation = positionAnnotation;
        }
        observationAnnotation := _nag_to_observation_annotation(nag);
        if observationAnnotation != .None {
            Basic.array_add(*position.observationAnnotations, observationAnnotation);
        }
    }

    return nag != .None;
}

_parse_word :: (bytes : *string) -> string {
    word : string;
    word.data = bytes.data;

    while (<<bytes)[0] != #char " " && (<<bytes)[0] != #char "\n" {
        word.count += 1;
        Basic.advance(bytes);
    }

    return word;
}
