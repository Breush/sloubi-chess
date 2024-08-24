// @note: Should not be called directly.
load_pgn :: (bytes : string, game : *Game) -> bool {
    if bytes.count == 0 {
        // Somehow, we don't have bytes (cache issue?)
        return false;
    }

    skip_bom(*bytes);
    skip_blanks(*bytes);

    // Parsing each game - @todo should warn about bad usage of this function, then.
    while bytes.count > 0 && bytes[0] == #char "[" {
        game_setup_main_variation(game);
        rootPly := variation_add_ply(game.mainVariation);
        rootPly.position = get_starting_position();

        // Parsing tags
        while bytes.count > 0 && bytes[0] == #char "[" {
            Basic.advance(*bytes);
            tagName := parse_word(*bytes);
            Basic.advance(*bytes);
            Basic.advance(*bytes); // Skipping the quote.

            if tagName == "FEN" {
                rootPly.position = load_fen(bytes);
            } else if tagName == "BoardOrientation" {
                game.tags[TagName.BoardOrientation].color = ifx bytes[0] == #char "W" then Color.White else Color.Black;
            } else if tagName == "Event" { game.tags[TagName.Event].str = _read_tag(*bytes);
            } else if tagName == "Site"  { game.tags[TagName.Site].str = _read_tag(*bytes);
            } else if tagName == "Date"  { game.tags[TagName.Date].str  = _read_tag(*bytes);
            } else if tagName == "Round" { game.tags[TagName.Round].str = _read_tag(*bytes);
            } else if tagName == "White" { game.tags[TagName.White].str = _read_tag(*bytes);
            } else if tagName == "Black" { game.tags[TagName.Black].str = _read_tag(*bytes);
            } else if tagName == "Result" {
                // :ResultInPosition Currently ignored here.
                // _, result := _parse_potential_result(*bytes);
                // game.tags[TagName.Result].result = result;
            } else if tagName == "WhiteElo" { game.tags[TagName.WhiteElo].number = cast(u32) Basic.to_integer(_parse_to_end_of_string(*bytes));
            } else if tagName == "BlackElo" { game.tags[TagName.BlackElo].number = cast(u32) Basic.to_integer(_parse_to_end_of_string(*bytes));
            } else if tagName == "Title" {
                Basic.free(game.title);
                game.title = _read_tag(*bytes);
                game.autoTitle = false;
            } else if tagName == "Kind" {
                game.kind = ifx _parse_to_end_of_string(*bytes) == "Puzzle" then .Puzzle else .None;
                game.autoTitle = false;
            } else if tagName == "SetUp" { // Ignored too. (Kind of duplicate with FEN.)
            } else {
                extraTag := Basic.array_add(*game.extraTags);
                extraTag.name = Basic.copy_string(tagName);
                extraTag.value = _read_tag(*bytes);
            }

            _skip_to_end_of_tag(*bytes);
            skip_blanks(*bytes);
        }

        // Parsing main variation (and therefore its subvariations)
        _parse_variation(*bytes, game, game.mainVariation);
        skip_blanks(*bytes);

        // Allow parsing of multiple games in the same game. Yeah, I know, it's a bit weird.
        // However, it allows to write a small digression in the middle of a game, which is
        // very useful for writing book-like studies.
        while bytes.count > 0 && bytes[0] != #char "[" {
            rootPly := variation_add_ply(game.mainVariation);
            rootPly.position = get_starting_position();
            rootPly.first = true;
            _parse_variation(*bytes, game, game.mainVariation);
            skip_blanks(*bytes);
        }
    }

    Chamber._CHECK(bytes.count == 0, "PGN file parsing has some unparsed leftovers.");

    return true;
}

write_pgn :: (sb : *Basic.String_Builder, game : *Game) {
    if game.mainVariation == null {
        gameBytes := String.trim_right(game.bytes, "\r\n\t ");
        Basic.print_to_builder(sb, "%\n", gameBytes);
    } else {
        write_pgn_from_plies(sb, game);
    }
}

write_pgn_from_plies :: (sb : *Basic.String_Builder, game : *Game) {
    tag_or_qmark :: inline (tag : string, qmark := "?") -> string {
        return ifx tag != "" then tag else qmark;
    }

    // Standard tags
    Basic.print_to_builder(sb, "[Event \"%\"]\n", tag_or_qmark(game.tags[TagName.Event].str));
    Basic.print_to_builder(sb, "[Site \"%\"]\n", tag_or_qmark(game.tags[TagName.Site].str));
    Basic.print_to_builder(sb, "[Date \"%\"]\n", tag_or_qmark(game.tags[TagName.Date].str, "????.??.??"));
    Basic.print_to_builder(sb, "[Round \"%\"]\n", tag_or_qmark(game.tags[TagName.Round].str));
    Basic.print_to_builder(sb, "[White \"%\"]\n", tag_or_qmark(game.tags[TagName.White].str));
    Basic.print_to_builder(sb, "[Black \"%\"]\n", tag_or_qmark(game.tags[TagName.Black].str));
    Basic.print_to_builder(sb, "[Result \"%\"]\n", result_to_ascii(Basic.peek(game.mainVariation.plies).position.result));

    // Custom tags
    if game.tags[TagName.WhiteElo].number != 0 {
        Basic.print_to_builder(sb, "[WhiteElo \"%\"]\n", game.tags[TagName.WhiteElo].number);
    }
    if game.tags[TagName.BlackElo].number != 0 {
        Basic.print_to_builder(sb, "[BlackElo \"%\"]\n", game.tags[TagName.BlackElo].number);
    }
    if !game.autoTitle && game.title.count != 0 {
        Basic.print_to_builder(sb, "[Title \"%\"]\n", game.title);
    }
    if game.kind != .None {
        Basic.print_to_builder(sb, "[Kind \"%\"]\n", game.kind);
    }

    boardOrientation := game.tags[TagName.BoardOrientation].color;
    if boardOrientation != .White {
        Basic.print_to_builder(sb, "[BoardOrientation \"%\"]\n", boardOrientation);
    }
    if !position_is_starting_one(game.mainVariation.plies[0].position) {
        Basic.append(sb, "[SetUp \"1\"]\n");
        Basic.print_to_builder(sb, "[FEN \"%\"]\n", position_to_fen(game.mainVariation.plies[0].position));
    }

    // Extra tags
    for extraTag : game.extraTags {
        Basic.print_to_builder(sb, "[% \"%\"]\n", extraTag.name, extraTag.value);
    }
    Basic.append(sb, "\n");

    // The game itself
    gameBuilder : Basic.String_Builder;
    _write_variation(*gameBuilder, game.mainVariation);

    // There is officially a column limit of 80 for PGNs,
    // so we can't write that as it is.
    gameString := Basic.builder_to_string(*gameBuilder);
    while gameString.count > 80 {
        endOfLineIndex := 0;
        while endOfLineIndex < 80 && gameString[endOfLineIndex] != #char "\n" {
            endOfLineIndex += 1;
        }
        if endOfLineIndex == 80 {
            while endOfLineIndex > 0 && gameString[endOfLineIndex] != #char " " {
                endOfLineIndex -= 1;
            }
            if endOfLineIndex == 0 then break; // One stupid long word without blanks, just don't care.
        }

        lineString : string;
        lineString.data = gameString.data;
        lineString.count = endOfLineIndex;
        Basic.print_to_builder(sb, "%\n", lineString);
        Basic.advance(*gameString, endOfLineIndex + 1);
    }
    gameString = String.trim_right(gameString, "\n ");

    if String.trim_right(gameString, "\n ").count == 0 {
        Basic.append(sb, "{[%cmt Empty]}\n");
    } else {
        Basic.print_to_builder(sb, "%\n", String.trim_right(gameString, "\n "));
    }
}

_write_variation :: (builder : *Basic.String_Builder, variation : *VariationEntity) {
    for ply, plyIndex : variation.plies {
        if ply.first && ply.position.comment.count == 0 && ply.variations.count == 0 then continue;

        if !ply.first {
            moveIndex := (ply.position.moveIndex + 1) / 2;
            previousPly := variation.plies[plyIndex - 1];

            // Don't write black move index if context is clear (no comment nor variation before).
            needMoveIndex := true;
            if ply.position.moveIndex % 2 == 0 {
                if previousPly.index != 0 && previousPly.position.comment.count == 0 && previousPly.variations.count == 0 {
                    needMoveIndex = false;
                }
            }
            if needMoveIndex {
                Basic.print_to_builder(builder, "%.% ", moveIndex, ifx ply.position.moveIndex % 2 then "" else "..");
            }

            Basic.append(builder, position_move_to_san(previousPly.position, ply.position, false));
            _write_nags(builder, *ply.position);
        }

        if ply.position.comment.count != 0 {
            if !ply.first {
                Basic.append(builder, " ");
            }
            _write_escaped_comment(builder, ply.position.comment);
        }

        if ply.position.tags.count != 0 {
            // Iterating in a known tag order.
            for tagId : 0 .. TagName.Count - 1 {
                tagName := cast(TagName) tagId;
                tagValue := Hash.table_find_pointer(*ply.position.tags, tagName);
                if tagValue == null then continue;

                Basic.print_to_builder(builder, "\n{[%%tag % ", tagName);
                if #complete tagName == {
                    case .Event; Basic.print_to_builder(builder, "\"%\"", tagValue.str);
                    case .Site; Basic.print_to_builder(builder, "\"%\"", tagValue.str);
                    case .Date; Basic.print_to_builder(builder, "\"%\"", tagValue.str);
                    case .Round; Basic.print_to_builder(builder, "\"%\"", tagValue.str);
                    case .White; Basic.print_to_builder(builder, "\"%\"", tagValue.str);
                    case .Black; Basic.print_to_builder(builder, "\"%\"", tagValue.str);
                    // :ResultInPosition
                    // case .Result; Basic.print_to_builder(builder, "%", result_to_ascii(tagValue.result));
                    case .WhiteElo; Basic.print_to_builder(builder, "\"%\"", tagValue.number);
                    case .BlackElo; Basic.print_to_builder(builder, "\"%\"", tagValue.number);
                    case .BoardOrientation; Basic.print_to_builder(builder, "\"%\"", tagValue.color);
                    case .Count;
                }
                Basic.append(builder, "]}");
            }
        }

        if ply.customPosition {
            Basic.print_to_builder(builder, "\n{[%%tag FEN \"%\"]}", position_to_fen(ply.position));
        }

        if ply.position.highlights.squares.count != 0 {
            Basic.append(builder, " {[%csl ");
            for squareHighlight, index : ply.position.highlights.squares {
                Basic.print_to_builder(builder, "%1%2", highlight_color_to_string(squareHighlight.color), coord_to_algebraic(squareHighlight.coord));
                if index != ply.position.highlights.squares.count - 1 {
                    Basic.append(builder, ",");
                }
            }
            Basic.append(builder, "]}");
        }

        if ply.position.highlights.arrows.count != 0 {
            Basic.append(builder, " {[%cal ");
            for arrowHighlight, index : ply.position.highlights.arrows {
                Basic.print_to_builder(builder, "%1%2%3", highlight_color_to_string(arrowHighlight.color), coord_to_algebraic(arrowHighlight.fromCoord), coord_to_algebraic(arrowHighlight.toCoord));
                if index != ply.position.highlights.arrows.count - 1 {
                    Basic.append(builder, ",");
                }
            }
            Basic.append(builder, "]}");
        }

        if ply.variations.count != 0 {
            if !ply.first || ply.position.comment.count != 0 {
                Basic.append(builder, " ");
            }
            for subVariation, subVariationIndex : ply.variations {
                Basic.append(builder, "(");
                _write_variation(builder, subVariation);
                Basic.append(builder, ")");
                if subVariationIndex != ply.variations.count - 1 {
                    Basic.append(builder, " ");
                }
            }
        }

        _write_result(builder, *ply.position);

        if plyIndex != variation.plies.count - 1 && ply.position.result == .None {
            Basic.append(builder, " ");
        }
    }
}

_write_nags :: (builder : *Basic.String_Builder, position : *Position) {
    if position.lastMove.annotation != .None {
        Basic.print_to_builder(builder, " $%", cast(u32) _annotation_to_nag(position.lastMove.annotation));
    }
    if position.annotation != 0 {
        Basic.print_to_builder(builder, " $%", cast(u32) _annotation_to_nag(position.annotation));
    }
    for observationAnnotation : position.observationAnnotations {
        Basic.print_to_builder(builder, " $%", cast(u32) _annotation_to_nag(observationAnnotation));
    }
}

_write_result :: (builder : *Basic.String_Builder, position : *Position) {
    if position.result == .WhiteWins ||
       position.result == .BlackWins ||
       position.result == .Draw ||
       position.result == .Unknown {
        Basic.print_to_builder(builder, " %\n\n", result_to_ascii(position.result));
    }
}

_write_escaped_comment :: (builder : *Basic.String_Builder, comment : string) {
    Basic.append(builder, "{");
    for i : 0..comment.count - 1 {
        if comment[i] == #char "}" then Basic.append(builder, "\\}");
        else if comment[i] == #char "[" then Basic.append(builder, "\\[");
        else if comment[i] == #char "\n" then Basic.append(builder, "\\n");
        else Basic.append(builder, comment[i]);
    }
    Basic.append(builder, "}");
}

#scope_file

knownIgnoredTagNames : Hash.Table(string, bool);

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

_skip_to_end_of_tag :: inline (bytes : *string) {
    skip_until(bytes, #char "]");
}

_read_tag :: inline (bytes : *string) -> string {
    tag := _parse_to_end_of_string(bytes);
    if tag == "" || tag == "?" then return "";
    return Basic.copy_string(tag);
}

_parse_to_end_of_string :: (bytes : *string) -> string {
    return parse_until(bytes, .[ #char "\"" ]);
}

_parse_move_number :: (bytes : *string) {
    while bytes.count > 0 &&
          bytes.*[0] != #char "." {
        if bytes.*[0] < #char "0" || bytes.*[0] > #char "9" {
            bytes.count = Basic.min(bytes.count, 10);
            Basic.log("Was expecting a move number here: %", bytes.*, flags=.ERROR);
        }

        Basic.advance(bytes);
    }

    while bytes.count > 0 && bytes.*[0] == #char "." {
        Basic.advance(bytes);
    }

    if bytes.count > 0 {
        Basic.advance(bytes);
    }

    skip_blanks(bytes);
}

_parse_potential_move_number :: (bytes : *string) -> bool {
    if bytes.*[0] < #char "0" || bytes.*[0] > #char "9" {
        return false;
    }
    if bytes.*[1] == #char "-" || bytes.*[1] == #char "/" { // Don't parse a result as if it was a move number.
        return false;
    }

    _parse_move_number(bytes);
    return true;
}

_parse_potential_move :: (bytes : *string, variation : *VariationEntity) -> bool {
    if bytes.*[0] != #char "O" && bytes.*[0] != #char "B" && bytes.*[0] != #char "K" &&
       bytes.*[0] != #char "N" && bytes.*[0] != #char "R" && bytes.*[0] != #char "Q" &&
       (bytes.*[0] < #char "a" || bytes.*[0] > #char "h") {
        return false;
    }

    lastPosition := *Basic.peek(variation.plies).position;

    position : Position;
    position_copy_state_from(*position, lastPosition);
    color := position_color_to_play(*position);

    capture : bool;
    sourceCoord, targetCoord : Coord = 0xFF, 0xFF;
    promotionPieceKind : PieceKind;

    piece : Piece;
    piece.color = color;

    // Pawn move
    if bytes.*[0] >= #char "a" && bytes.*[0] <= #char "h" {
        piece.kind = .Pawn;

        sourceHintCoord : Coord = 0xFF;
        sourceHintCoord, targetCoord, capture = _parse_pgn_move(bytes);

        coord_copy_row(*sourceHintCoord, targetCoord);
        if !capture {
            coord_copy_col(*sourceHintCoord, targetCoord);
        }

        // Find the source square of the piece
        rowDirection := ifx color == .White then cast(s8) -1 else cast(s8) 1;
        sourceCoord = position_find_piece_in_direction(lastPosition, piece, 0xFF, sourceHintCoord, rowDirection, 0, 2);

        // Checking for promotion
        promotionPieceKind = _parse_potential_promotion(bytes);
    }
    // Castling
    else if bytes.*[0] == #char "O" {
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

    _parse_potential_check(bytes);
    _parse_potential_mate(bytes);
    skip_blanks(bytes);

    // Updating the game
    if coord_is_valid(sourceCoord) {
        position_play_move(*position, sourceCoord, targetCoord, promotionPieceKind);

        ply := variation_add_ply(variation);
        ply.position = position;
    }

    return true;
}

_parse_potential_col :: (bytes : *string) -> u8 {
    if bytes.*[0] >= #char "a" && bytes.*[0] <= #char "h" {
        return _parse_col(bytes, check = false);
    }
    return 0xFF;
}

_parse_potential_row :: (bytes : *string) -> u8 {
    if bytes.*[0] >= #char "1" && bytes.*[0] <= #char "8" {
        return _parse_row(bytes, check = false);
    }
    return 0xFF;
}

_parse_potential_expected :: (bytes : *string, c : u8) -> bool {
    if bytes.*[0] == c {
        Basic.advance(bytes);
        return true;
    }
    return false;
}

_parse_expected :: (bytes : *string, c : u8) -> bool {
    leftovers := bytes.*;
    leftovers.count = Basic.min(leftovers.count, 200);
    Chamber._CHECK(bytes.*[0] == c, "Was expecting a '%' here: %", Basic.to_string(*c, 1), leftovers);
    Basic.advance(bytes);
    return true;
}

_parse_col :: (bytes : *string, $check := true) -> u8 {
    #if check then Chamber._CHECK(bytes.*[0] >= #char "a" && bytes.*[0] <= #char "h", 0xFF, "Was expecting a column here: %", bytes.*);
    col := bytes.*[0] - #char "a";
    Basic.advance(bytes);
    return col;
}

_parse_row :: (bytes : *string, $check := true) -> u8 {
    #if check then Chamber._CHECK(bytes.*[0] >= #char "1" && bytes.*[0] <= #char "8", 0xFF, "Was expecting a row here: %", bytes.*);
    col := bytes.*[0] - #char "1";
    Basic.advance(bytes);
    return col;
}

_parse_potential_capture :: (bytes : *string) -> bool {
    if bytes.*[0] == #char "x" {
        Basic.advance(bytes);
        return true;
    }
    return false;
}

_parse_potential_check :: (bytes : *string) -> bool {
    if bytes.*[0] == #char "+" {
        Basic.advance(bytes);
        return true;
    }
    return false;
}

_parse_potential_mate :: (bytes : *string) -> bool {
    if bytes.*[0] == #char "#" {
        Basic.advance(bytes);
        return true;
    }
    return false;
}

_parse_potential_promotion :: (bytes : *string) -> PieceKind {
    if bytes.*[0] != #char "=" then return .None;
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

    return coord(sourceHintRow, sourceHintCol), coord(targetRow, targetCol), capture;
}

_parse_piece_kind :: (bytes : *string) -> PieceKind {
    pieceKind := PieceKind.None;

    if      bytes.*[0] == #char "B" then pieceKind = .Bishop;
    else if bytes.*[0] == #char "K" then pieceKind = .King;
    else if bytes.*[0] == #char "N" then pieceKind = .Knight;
    else if bytes.*[0] == #char "Q" then pieceKind = .Queen;
    else if bytes.*[0] == #char "R" then pieceKind = .Rook;
    else {
        Basic.log("Unable to parse piece kind here: %", bytes.*, flags = .ERROR);
    }

    Basic.advance(bytes);
    return pieceKind;
}

_parse_potential_result :: (bytes : *string) -> (bool, Result) {
    if bytes.*[0] == #char "1" {
        // Peeking
        if bytes.*[1] == #char "-" {
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "-");
            _parse_expected(bytes, #char "0");
            return true, .WhiteWins;
        } else if bytes.*[1] == #char "/" {
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "/");
            _parse_expected(bytes, #char "2");
            _parse_expected(bytes, #char "-");
            _parse_expected(bytes, #char "1");
            _parse_expected(bytes, #char "/");
            _parse_expected(bytes, #char "2");
            return true, .Draw;
        }
    } else if bytes.*[0] == #char "0" {
        _parse_expected(bytes, #char "0");
        _parse_expected(bytes, #char "-");
        _parse_expected(bytes, #char "1");
        return true, .BlackWins;
    } else if bytes.*[0] == #char "*" {
        _parse_expected(bytes, #char "*");
        return true, .Unknown;
    }

    return false, .Unknown;
}

_parse_potential_comment :: (bytes : *string, ply : *PlyEntity) -> (string, bool) {
    if bytes.count == 0 then return "", false;
    if bytes.*[0] != #char "{" then return "", false;
    Basic.advance(bytes);
    skip_blanks(bytes);

    position := *ply.position;

    sb : Basic.String_Builder;
    sb.allocator = Basic.temp;

    whitespacesToTrim := 0;
    previousIsBackslash := false;
    while previousIsBackslash || bytes.*[0] != #char "}" {
        if previousIsBackslash {
            if bytes.*[0] == #char "n" then Basic.append(*sb, #char "\n");
            else Basic.append(*sb, bytes.*[0]);
            previousIsBackslash = false;
            Basic.advance(bytes);
            continue;
        }

        previousIsBackslash = !previousIsBackslash && bytes.*[0] == #char "\\";
        if bytes.*[0] == #char " " then whitespacesToTrim += 1;
        else whitespacesToTrim = 0;

        if bytes.*[0] == #char "\n" then Basic.append(*sb, #char " ");
        else if !previousIsBackslash {
            // Special command.
            if bytes.*[0] == #char "[" && bytes.*[1] == #char "%" {
                Basic.advance(bytes, 2);
                commandName := parse_word(bytes);
                Basic.advance(bytes);

                // Square highlight command.
                if commandName == "csl" then _parse_square_highlights(bytes, position);
                else if commandName == "cal" then _parse_arrow_highlights(bytes, position);
                else if commandName == "clk" then _parse_clock(bytes, position);
                else if commandName == "tag" {
                    tagName := parse_word(bytes);
                    skip_until(bytes, #char "\"");
                    if tagName == "FEN" {
                        ply.customPosition = true;
                        position_copy_state_from(position, load_fen(bytes.*));
                    }
                    else if tagName == "Event" then position_set_tag(position, .Event, .{ str = _read_tag(bytes) });
                    else if tagName == "Site" then position_set_tag(position, .Site, .{ str = _read_tag(bytes) });
                    else if tagName == "Date" then position_set_tag(position, .Date, .{ str = _read_tag(bytes) });
                    else if tagName == "Round" then position_set_tag(position, .Round, .{ str = _read_tag(bytes) });
                    else if tagName == "White" then position_set_tag(position, .White, .{ str = _read_tag(bytes) });
                    else if tagName == "Black" then position_set_tag(position, .Black, .{ str = _read_tag(bytes) });
                    else if tagName == "WhiteElo" then position_set_tag(position, .WhiteElo, .{ number = cast(u32) Basic.to_integer(_parse_to_end_of_string(bytes)) });
                    else if tagName == "BlackElo" then position_set_tag(position, .BlackElo, .{ number = cast(u32) Basic.to_integer(_parse_to_end_of_string(bytes)) });
                    else if tagName == "Title" {} // NoOp
                    else if tagName == "BoardOrientation" {
                        color := ifx bytes.*[0] == #char "W" then Color.White else .Black;
                        position_set_tag(position, .BoardOrientation, .{ color = color });
                    }
                    else if Hash.table_find_pointer(*knownIgnoredTagNames, tagName) == null {
                        Hash.table_add(*knownIgnoredTagNames, tagName, true);
                        Basic.log("Unknown name in tag command: %", tagName, flags = .WARNING);
                    }
                } else if commandName == "eval" {
                    // @todo Currently doing nothing... Maybe store it at least?
                } else {
                    Basic.log("Unknown PGN command name: %", commandName, flags = .WARNING);
                }

                while bytes.*[0] != #char "]" {
                    Basic.advance(bytes);
                }
            } else {
                Basic.append(*sb, bytes.*[0]);
            }
        }
        Basic.advance(bytes);
    }
    Basic.advance(bytes);
    skip_blanks(bytes);

    str := Basic.builder_to_string(*sb,, Basic.temp);
    str.count -= whitespacesToTrim;
    return str, true;
}

_parse_potential_comments :: (bytes : *string, variation : *VariationEntity) {
    fullComment : string;

    Basic.auto_release_temp();
    {
        while true {
            comment, ok := _parse_potential_comment(bytes, Basic.peek(variation.plies));
            if !ok then break;

            if fullComment.count == 0 then fullComment = comment;
            else if comment.count != 0 {
                fullComment = Basic.tprint("%\n%", fullComment, comment);
            }
        }
    }

    fullComment = String.trim(fullComment);
    if fullComment.count == 0 then return;

    Basic.peek(variation.plies).position.comment = Basic.copy_string(fullComment);
}

_parse_potential_variation :: (bytes : *string, game : *Game, parentVariation : *VariationEntity) -> bool {
    if bytes.count == 0 || bytes.*[0] != #char "(" then return false;
    Basic.advance(bytes);

    lastPly := Basic.peek(parentVariation.plies);
    variation := game_add_variation(game, lastPly);

    ply := variation_add_ply(variation);

    position_copy_state_from(*ply.position, parentVariation.plies[parentVariation.plies.count - 2].position);

    skip_blanks(bytes);
    _parse_variation(bytes, game, variation);

    skip_blanks(bytes);
    _parse_expected(bytes, #char ")");
    skip_blanks(bytes);
    return true;
}

_parse_variation :: (bytes : *string, game : *Game, variation : *VariationEntity) {
    lastBytesCount := 0;
    while bytes.count > 0 && bytes.count != lastBytesCount {
        _parse_potential_comments(bytes, variation);

        lastBytesCount = bytes.count;
        _parse_potential_comments(bytes, variation);
        while _parse_potential_variation(bytes, game, variation) {}
        if bytes.count == 0 || bytes.*[0] == #char ")" then break; // End of variation
        if !_parse_potential_annotated_move(bytes, game, variation) then break;
    }
}

// Returns false if this is the last move a variation.
_parse_potential_annotated_move :: (bytes : *string, game : *Game, variation : *VariationEntity) -> bool {
    // position_debug_dump(Basic.peek(variation.plies).position);
    if bytes.count == 0 then return false;

    _parse_potential_move_number(bytes);
    if _parse_potential_move(bytes, variation) {
        while _parse_potential_annotation(bytes, variation) {}
        _parse_potential_comments(bytes, variation);

        if bytes.count == 0 then return false;
        if bytes.*[0] == #char ")" then return false;
    }

    foundResult, result := _parse_potential_result(bytes);
    if foundResult then {
        Basic.peek(variation.plies).position.result = result;
        return false;
    }

    return true;
}

// Ignoring NAG et al. for now
_parse_potential_annotation :: (bytes : *string, variation : *VariationEntity) -> bool {
    if bytes.count == 0 then return false;

    nag : Nag;

    if bytes.*[0] == #char "$" {
        Basic.advance(bytes);
        ok : bool;
        nagValue : s64;
        nagValue, ok, bytes.* = Basic.to_integer(bytes.*);
        nag = cast(Nag) nagValue;
    }

    if bytes.*[0] == #char "!" {
        Basic.advance(bytes);
        if bytes.*[0] == #char "!" { nag = .Brillant; Basic.advance(bytes); }
        else if bytes.*[0] == #char "?" { nag = .Interesting; Basic.advance(bytes); }
        else nag = .Good;
    } else if bytes.*[0] == #char "?" {
        Basic.advance(bytes);
        if bytes.*[0] == #char "?" { nag = .Blunder; Basic.advance(bytes); }
        else if bytes.*[0] == #char "!" { nag = .Dubious; Basic.advance(bytes); }
        else nag = .Mistake;
    }

    skip_blanks(bytes);

    if nag != .None {
        position := *Basic.peek(variation.plies).position;
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
        coloredSquare := parse_until(bytes, .[#char "]", #char " ", #char ","]);
        if coloredSquare.count != 0 {
            squareHighlight := Basic.array_add(*position.highlights.squares);
            squareHighlight.color = highlight_color(coloredSquare[0]);
            Basic.advance(*coloredSquare);
            squareHighlight.coord = algebraic_to_coord(coloredSquare);
        }

        skip_blanks(bytes);
        if bytes.*[0] == #char "]" then break;
        Basic.advance(bytes);
    }
}

_parse_arrow_highlights :: (bytes : *string, position : *Position) {
    Basic.push_allocator(context.default_allocator);

    while true {
        coloredArrow := parse_until(bytes, .[#char "]", #char " ", #char ","]);
        if coloredArrow.count != 0 {
            arrowHighlight : ArrowHighlight;
            arrowHighlight.color = highlight_color(coloredArrow[0]);
            Basic.advance(*coloredArrow);
            arrowHighlight.fromCoord = algebraic_to_coord(coloredArrow);
            Basic.advance(*coloredArrow, 2);
            arrowHighlight.toCoord = algebraic_to_coord(coloredArrow);

            if coord_is_valid(arrowHighlight.fromCoord) && coord_is_valid(arrowHighlight.toCoord) {
                Basic.array_add(*position.highlights.arrows, arrowHighlight);
            }
        }

        skip_blanks(bytes);
        if bytes.*[0] == #char "]" then break;
        Basic.advance(bytes);
    }
}

_parse_clock :: (bytes : *string, position : *Position) {
    Basic.push_allocator(context.default_allocator);

    clock := parse_until(bytes, .[#char "]", #char " "]);

    if position_color_to_play(position) == .White {
        position.blackClock = Basic.copy_string(clock);
    } else {
        position.whiteClock = Basic.copy_string(clock);
    }
}
