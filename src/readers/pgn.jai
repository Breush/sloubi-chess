
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

    read_tag :: inline (bytes : *string) -> string {
        tag := _parse_to_end_of_string(bytes);
        if tag == "" || tag == "?" then return "";
        return Basic.copy_string(tag);
    }

    while bytes[0] == #char "[" {
        Basic.advance(*bytes);
        tagName := _parse_word(*bytes);
        Basic.advance(*bytes);
        Basic.advance(*bytes); // Skipping the quote.

        if tagName == "FEN" {
            rootNode.position = load_fen(bytes);
        } else if tagName == "BoardOrientation" {
            game.boardOrientation = ifx bytes[0] == #char "W" then Color.White else Color.Black;
        } else if tagName == "Event" { game.tags.event = read_tag(*bytes);
        } else if tagName == "Site"  { game.tags.site  = read_tag(*bytes);
        } else if tagName == "Date"  { game.tags.date  = read_tag(*bytes);
        } else if tagName == "Round" { game.tags.round = read_tag(*bytes);
        } else if tagName == "White" { game.tags.white = read_tag(*bytes);
        } else if tagName == "Black" { game.tags.black = read_tag(*bytes);
        } else if tagName == "WhiteElo" { game.tags.whiteElo = cast(u16) Basic.to_integer(_parse_to_end_of_string(*bytes));
        } else if tagName == "BlackElo" { game.tags.blackElo = cast(u16) Basic.to_integer(_parse_to_end_of_string(*bytes));
        } else if tagName == "Result" { // Ignored, but silently.
        } else if tagName == "SetUp" { // Ignored too. (Kind of duplicate with FEN.)
        } else {
            tag := Basic.array_add(*game.tags.extra);
            tag.name = Basic.copy_string(tagName);
            tag.value = read_tag(*bytes);
        }

        _skip_to_end_of_tag(*bytes);
        _skip_blanks(*bytes);
    }

    // Parsing main variation (and therefore its subvariations)
    _parse_variation(*bytes, *game.mainVariation);
    _skip_blanks(*bytes);

    Chamber._CHECK(bytes.count == 0, Basic.tprint("Leftovers: %", bytes));

    instance.game.pgnFileName = Basic.copy_string(filename);
    game_show(*instance.game);

    return true;
}

save_pgn :: (filename : string) {
    Basic.push_allocator(Basic.temp);
    Basic.auto_release_temp();

    Basic.log("Saving PGN file %.", filename);

    builder : Basic.String_Builder;

    tag_or_qmark :: inline (tag : string) -> string {
        return ifx tag == "" then "?" else tag;
    }

    // Standard tags
    Basic.print_to_builder(*builder, "[Event \"%\"]\n", tag_or_qmark(instance.game.tags.event));
    Basic.print_to_builder(*builder, "[Site \"%\"]\n", tag_or_qmark(instance.game.tags.site));
    Basic.print_to_builder(*builder, "[Date \"%\"]\n", tag_or_qmark(instance.game.tags.date)); // @todo Not valid by spec, should be "????.??.??"
    Basic.print_to_builder(*builder, "[Round \"%\"]\n", tag_or_qmark(instance.game.tags.round));
    Basic.print_to_builder(*builder, "[White \"%\"]\n", tag_or_qmark(instance.game.tags.white));
    Basic.print_to_builder(*builder, "[Black \"%\"]\n", tag_or_qmark(instance.game.tags.black));
    Basic.print_to_builder(*builder, "[Result \"%\"]\n", game_result_to_string(instance.game.result));

    // Custom tags
    if instance.game.tags.whiteElo != 0 {
        Basic.print_to_builder(*builder, "[WhiteElo \"%\"]\n", instance.game.tags.whiteElo);
    }
    if instance.game.tags.blackElo != 0 {
        Basic.print_to_builder(*builder, "[BlackElo \"%\"]\n", instance.game.tags.blackElo);
    }
    if instance.game.boardOrientation != .White {
        Basic.print_to_builder(*builder, "[BoardOrientation \"%\"]\n", instance.game.boardOrientation);
    }
    if !position_is_starting_one(instance.game.mainVariation.nodes[0].position) {
        Basic.append(*builder, "[SetUp \"1\"]\n");
        Basic.print_to_builder(*builder, "[FEN \"%\"]\n", position_to_fen(instance.game.mainVariation.nodes[0].position));
    }

    // Extra tags
    for tag : instance.game.tags.extra {
        Basic.print_to_builder(*builder, "[% \"%\"]\n", tag.name, tag.value);
    }
    Basic.append(*builder, "\n");

    // The game itself
    gameBuilder : Basic.String_Builder;
    _write_variation(*gameBuilder, *instance.game.mainVariation);
    Basic.print_to_builder(*gameBuilder, " %", game_result_to_string(instance.game.result));

    // There is officially a column limit of 80 for PGNs,
    // so we can't write that as it is.
    gameString := Basic.builder_to_string(*gameBuilder);
    while gameString.count > 80 {
        endOfLineIndex := 80;
        while endOfLineIndex > 0 && gameString[endOfLineIndex] != #char " " {
            endOfLineIndex -= 1;
        }
        if endOfLineIndex == 0 then break; // One stupid long word without blanks, just don't care.

        lineString : string;
        lineString.data = gameString.data;
        lineString.count = endOfLineIndex;
        Basic.print_to_builder(*builder, "%\n", lineString);
        Basic.advance(*gameString, endOfLineIndex + 1);
    }
    Basic.print_to_builder(*builder, "%\n", gameString);

    File.write_entire_file(filename, *builder);
}

_write_variation :: (builder : *Basic.String_Builder, variation : *Variation) {
    for node, index : variation.nodes {
        if index == 0 && node.comment.count == 0 && node.variations.count == 0 then continue;

        if index != 0 {
            moveIndex := (node.position.moveIndex + 1) / 2;
            Basic.print_to_builder(builder, "%.% %", moveIndex, ifx node.position.moveIndex % 2 then "" else "..", position_last_move_to_san(node.position, annotations = false));
            _write_nags(builder, *node.position);
        }

        if node.comment.count != 0 {
            if index != 0 {
                Basic.append(builder, " ");
            }
            _write_escaped_comment(builder, node.comment);
        }

        if node.position.squareHighlights.count != 0 {
            Basic.append(builder, " {[%csl ");
            for squareHighlight, index : node.position.squareHighlights {
                Basic.print_to_builder(builder, "%1%2", highlight_color_to_string(squareHighlight.color), coord_to_algebraic(squareHighlight.coord));
                if index != node.position.squareHighlights.count - 1 {
                    Basic.append(builder, ",");
                }
            }
            Basic.append(builder, "]}");
        }

        if node.variations.count != 0 {
            if index != 0 || node.comment.count != 0 {
                Basic.append(builder, " ");
            }
            for subVariation, subVariationIndex : node.variations {
                Basic.append(builder, "(");
                _write_variation(builder, subVariation);
                Basic.append(builder, ")");
                if subVariationIndex != node.variations.count - 1 {
                    Basic.append(builder, " ");
                }
            }
        }

        if index != variation.nodes.count - 1 {
            Basic.append(builder, " ");
        }
    }
}

_write_nags :: (builder : *Basic.String_Builder, position : *Position) {
    if position.lastMove.annotation != .None {
        Basic.print_to_builder(builder, " $%", cast(u32) _annotation_to_nag(position.lastMove.annotation));
    }
    if position.annotation != .None {
        Basic.print_to_builder(builder, " $%", cast(u32) _annotation_to_nag(position.annotation));
    }
    for observationAnnotation : position.observationAnnotations {
        Basic.print_to_builder(builder, " $%", cast(u32) _annotation_to_nag(observationAnnotation));
    }
}

_write_escaped_comment :: (builder : *Basic.String_Builder, comment : string) {
    Basic.append(builder, "{");
    for i : 0..comment.count - 1 {
        if comment[i] == #char "}" then Basic.append(builder, "\\}");
        else if comment[i] == #char "[" then Basic.append(builder, "\\[");
        else Basic.append(builder, comment[i]);
    }
    Basic.append(builder, "}");
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

_annotation_to_nag :: (moveAnnotation : MoveAnnotation) -> Nag {
    if #complete moveAnnotation == {
        case .None; return .None;
        case .Good; return .Good;
        case .Mistake; return .Mistake;
        case .Brillant; return .Brillant;
        case .Blunder; return .Blunder;
        case .Interesting; return .Interesting;
        case .Dubious; return .Dubious;
        case .Forced; return .Forced;
        case .Zugzwang; return .WhiteZugzwang; // @todo :BlackOrWhiteUnclearAnnotation Do we care about white or black here?
    }
    return .None;
}

_annotation_to_nag :: (positionAnnotation : PositionAnnotation) -> Nag {
    if #complete positionAnnotation == {
        case .None; return .None;
        case .Drawish; return .Drawish;
        case .Unclear; return .Unclear;
        case .WhiteSlightAdvantage; return .WhiteSlightAdvantage;
        case .BlackSlightAdvantage; return .BlackSlightAdvantage;
        case .WhiteModerateAdvantage; return .WhiteModerateAdvantage;
        case .BlackModerateAdvantage; return .BlackModerateAdvantage;
        case .WhiteDecisiveAdvantage; return .WhiteDecisiveAdvantage;
        case .BlackDecisiveAdvantage; return .BlackDecisiveAdvantage;
    }
    return .None;
}

_annotation_to_nag :: (observationAnnotation : ObservationAnnotation) -> Nag {
    if #complete observationAnnotation == {
        case .None; return .None;
        case .SpaceAdvantage; return .WhiteModerateSpaceAdvantage; // :BlackOrWhiteUnclearAnnotation
        case .TimeAdvantage; return .WhiteModerateTimeAdvantage; // :BlackOrWhiteUnclearAnnotation
        case .Initiative; return .WhiteInitiative; // :BlackOrWhiteUnclearAnnotation
        case .Attack; return .WhiteAttack; // :BlackOrWhiteUnclearAnnotation
        case .Compensation; return .WhiteSufficientCompensation; // :BlackOrWhiteUnclearAnnotation
        case .Counterplay; return .WhiteModerateCounterplay; // :BlackOrWhiteUnclearAnnotation
        case .TimeControlPressure; return .WhiteModerateTimeControlPressure; // :BlackOrWhiteUnclearAnnotation
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

_parse_to_end_of_string :: (bytes : *string) -> string {
    result := <<bytes;
    result.count = 0;
    c := (<<bytes)[0];
    while c != #char "\"" {
        Basic.advance(bytes);
        result.count += 1;
        c = (<<bytes)[0];
    }
    Basic.advance(bytes);
    return result;
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
    lastPosition := *Basic.peek(variation.nodes).position;

    position : Position;
    position.board = lastPosition.board;
    position.moveIndex = lastPosition.moveIndex;
    position.movesSinceLastCaptureOrPawnMove = lastPosition.movesSinceLastCaptureOrPawnMove;

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
    position.check = _parse_potential_check(bytes);
    position.mate = _parse_potential_mate(bytes);
    _skip_blanks(bytes);

    // Updating the game
    if coord_is_valid(sourceCoord) {
        position_play_move(*position, sourceCoord, targetCoord, promotionPieceKind);

        node := game_add_variation_node(*instance.game, variation);
        node.position = position;
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

_parse_potential_result :: (bytes : *string) -> (bool, Game.Result) {
    if (<<bytes)[0] == #char "1" {
        // Peeking
        if (<<bytes)[1] == #char "-" {
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "-");
            _parse_expected(bytes, #char "0");
            return true, .WhiteWin;
        } else if (<<bytes)[1] == #char "/" {
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "/");
            _parse_expected(bytes, #char "2");
            _parse_expected(bytes, #char "-");
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "/");
            _parse_expected(bytes, #char "2");
            return true, .Draw;
        }
    } else if (<<bytes)[0] == #char "0" {
        _parse_expected(bytes, #char "0");
        _parse_expected(bytes, #char "-");
        _parse_expected(bytes, #char "1");
        return true, .BlackWin;
    } else if (<<bytes)[0] == #char "*" {
        _parse_expected(bytes, #char "*");
        return true, .Unknown;
    }

    return false, .Unknown;
}

_parse_potential_comment :: (bytes : *string, position : *Position) -> (string, bool) {
    if bytes.count == 0 then return ("", false);
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
                Basic.advance(bytes, 2);
                commandName := _parse_word(bytes);
                Basic.advance(bytes);

                // Square highlight command.
                if commandName == "csl" {
                    _parse_square_highlights(bytes, position);
                } else {
                    Basic.log("Unknown PGN command name: %", commandName, flags = .WARNING);
                }

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

    Basic.auto_release_temp();
    {
        Basic.push_allocator(Basic.temp);

        while true {
            comment, ok := _parse_potential_comment(bytes, *Basic.peek(variation.nodes).position);
            if !ok then break;

            if fullComment.count == 0 then fullComment = comment;
            else if comment.count != 0 {
                fullComment = Basic.sprint("%\n%", fullComment, comment);
            }
        }
    }

    Basic.peek(variation.nodes).comment = Basic.copy_string(fullComment);
}

_parse_potential_variation :: (bytes : *string, parentVariation : *Variation, color : Color) -> bool {
    if (<<bytes)[0] != #char "(" then return false;
    Basic.advance(bytes);

    lastNode := Basic.peek(parentVariation.nodes);
    variation := game_add_variation(*instance.game, lastNode);

    node := game_add_variation_node(*instance.game, variation);
    node.position = parentVariation.nodes[parentVariation.nodes.count - 2].position;

    _skip_blanks(bytes);
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

// Returns false if this is the last move a variation.
_parse_potential_annotated_move :: (bytes : *string, variation : *Variation, color : Color) -> bool {
    // position_debug_dump(Basic.peek(variation.nodes).position);

    _parse_potential_move_number(bytes);
    _parse_move(bytes, variation, color);
    while _parse_potential_annotation(bytes, variation) {}
    _parse_potential_comments(bytes, variation);

    if bytes.count == 0 then return false;
    if (<<bytes)[0] == #char ")" then return false;

    foundResult, result := _parse_potential_result(bytes);
    if foundResult then {
        instance.game.result = result;
        return false;
    }

    return true;
}

// Ignoring NAG et al. for now
_parse_potential_annotation :: (bytes : *string, variation : *Variation) -> bool {
    if bytes.count == 0 then return false;

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
        else if (<<bytes)[0] == #char "?" { nag = .Interesting; Basic.advance(bytes); }
        else nag = .Good;
    } else if (<<bytes)[0] == #char "?" {
        Basic.advance(bytes);
        if (<<bytes)[0] == #char "?" { nag = .Blunder; Basic.advance(bytes); }
        else if (<<bytes)[0] == #char "!" { nag = .Dubious; Basic.advance(bytes); }
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

_parse_square_highlights :: (bytes : *string, position : *Position) {
    Basic.push_allocator(context.default_allocator);

    while true {
        coloredSquare := _parse_until(bytes, .[#char "]", #char " ", #char ","]);
        if coloredSquare.count != 0 {
            squareHighlight := Basic.array_add(*position.squareHighlights);
            squareHighlight.color = highlight_color(coloredSquare[0]);
            Basic.advance(*coloredSquare);
            squareHighlight.coord = algebraic_to_coord(coloredSquare);
        }

        _skip_blanks(bytes);
        if (<<bytes)[0] == #char "]" then break;
        Basic.advance(bytes);
    }
}

_parse_until :: (bytes : *string, characters : []u8) -> string {
    word : string;
    word.data = bytes.data;

    while true {
        for character : characters {
            if (<<bytes)[0] == character then return word;
        }

        word.count += 1;
        Basic.advance(bytes);
    }

    return word;
}

_parse_word :: (bytes : *string) -> string {
    return _parse_until(bytes, .[#char " ", #char "\n"]);
}
