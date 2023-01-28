
/*
 * Board position with all positioned pieces,
 * and extra info (who's turn to play, castling rights, etc.).
 * This is basically a FEN with our extra layer.
 *
 * Absolutely no restriction on being a valid position.
 *
 * @note Not trying to be perf-focused here, just easy to use.
 * The reason for that is because we're not doing a chess engine,
 * we won't required so much perf.
 */
Position :: struct {
    board : BoardPosition;

    comment : string;
    moveIndex : u16; // @note Therefore contains the color to play: even = white, odd = black.
    lastMove : AnnotatedMove;
    annotation : PositionAnnotation;
    observationAnnotations : [..]ObservationAnnotation;

    highlights : struct {
        squares : [..]SquareHighlight;
        arrows : [..]ArrowHighlight;
    }

    movesSinceLastCaptureOrPawnMove : u8;

    blackClock := "";
    whiteClock := "";

    flags : PositionFlags;
}

BoardPosition :: [CoordCount]Piece;

PositionFlags :: enum_flags u8 {
    None                            :: 0x00;
    Check                           :: 0x01;
    Mate                            :: 0x02;
    StaleMate                       :: 0x04;
    WhiteKingsideCastlingAllowed    :: 0x08;
    WhiteQueensideCastlingAllowed   :: 0x10;
    BlackKingsideCastlingAllowed    :: 0x20;
    BlackQueensideCastlingAllowed   :: 0x40;
    CastlingAllowedMask             :: WhiteKingsideCastlingAllowed | WhiteQueensideCastlingAllowed | BlackKingsideCastlingAllowed | BlackQueensideCastlingAllowed;
}

/*
 * Compact board position.
 * This is meant to represent a board position in a memory-efficiency way.
 * It's not easy to manipulate, so reserve this for when you need to store a lot of positions.
 *
 * We could go down further, for instance by storing a bitboard (64 bits) to know whether
 * a square is occupied, and then list of piece ids (4 bits each).
 * Which would make the whole thing 64 + 4 * 32 = 192 bits max (and 72 bits min).
 * But that would require dynamic allocations to store efficiently, which is a bit counter-productive.
 *
 * Therefore, I went for a flat array of 64 * 4 = 256 bits, which is less efficient,
 * but definitively easier to maintain. You can consider it like 4 bitboards each describing
 * a bit of a piece id.
 */
CompactBoardPosition :: [4]u64;

board_position :: (cbp : CompactBoardPosition) -> BoardPosition {
    bp : BoardPosition;
    for coord : 0 .. CoordCount - 1 {
        bit0 := cast(PieceId) ((cbp[0] >> coord) & 1);
        bit1 := cast(PieceId) ((cbp[1] >> coord) & 1);
        bit2 := cast(PieceId) ((cbp[2] >> coord) & 1);
        bit3 := cast(PieceId) ((cbp[3] >> coord) & 1);
        bp[coord] = piece_from_piece_id(bit0 | (bit1 << 1) | (bit2 << 2) | (bit3 << 3));
    }
    return bp;
}

compact_board_position :: (bp : BoardPosition) -> CompactBoardPosition {
    cbp : CompactBoardPosition;
    for coord : 0 .. CoordCount - 1 {
        pieceId := cast(u64) piece_id(bp[coord]);
        cbp[0] |= (pieceId & 1) << coord;
        cbp[1] |= ((pieceId >> 1) & 1) << coord;
        cbp[2] |= ((pieceId >> 2) & 1) << coord;
        cbp[3] |= ((pieceId >> 3) & 1) << coord;
    }
    return cbp;
}

// @note We call "move" what litterature might call "half-move".
SimpleMove :: struct {
    sourceCoord : Coord = 0xFF;
    targetCoord : Coord = 0xFF;
}

Move :: struct {
    using #as simpleMove : SimpleMove;
    promotionPieceKind := PieceKind.None;
}

AnnotatedMove :: struct {
    using #as move : Move;

    capture : bool;
    annotation : MoveAnnotation;
}

MoveAnnotation :: enum u8 {
    None :: 0;
    Good; // !
    Mistake; // ?
    Brillant; // ‼
    Blunder; // ⁇
    Interesting; // ⁉
    Dubious; // ⁈
    Forced; // □
    Zugzwang; // ⨀
}

PositionAnnotation :: enum u8 {
    None :: 0;
    Drawish; // =
    Unclear; // ∞
    WhiteSlightAdvantage; // ⩲
    BlackSlightAdvantage; // ⩱
    WhiteModerateAdvantage; // ±
    BlackModerateAdvantage; // ∓
    WhiteDecisiveAdvantage; // ∔
    BlackDecisiveAdvantage; // ∸
}

ObservationAnnotation :: enum u8 {
    None :: 0;
    SpaceAdvantage; // ○
    TimeAdvantage; // ↻
    Initiative; // ↑
    Attack; // →
    Compensation; // ≒
    Counterplay; // ⇆
    TimeControlPressure; // ⨁
    WithIdea; // ∆
    Novelty; // ℕ
}

SquareHighlight :: struct {
    color : HighlightColor;
    coord : Coord;
}

ArrowHighlight :: struct {
    color : HighlightColor;
    fromCoord : Coord;
    toCoord : Coord;
}

HighlightColor :: enum {
    None :: 0;
    Blue;
    Green;
    Red;
    Yellow;
}

STARTING_POSITION :: #run get_starting_position();

highlight_color :: () -> HighlightColor {
    if Sill.input_state(instance.engine, .ShiftLeft) ||
       Sill.input_state(instance.engine, .ShiftRight) {
        return .Green;
    } else if Sill.input_state(instance.engine, .ControlLeft) ||
              Sill.input_state(instance.engine, .ControlRight) {
        return .Yellow;
    } else if Sill.input_state(instance.engine, .AltLeft) ||
              Sill.input_state(instance.engine, .AltRight) {
        return .Blue;
    }
    return .Red;
}

highlight_color :: (character : u8) -> HighlightColor {
    if character == {
        case #char "B"; return .Blue;
        case #char "G"; return .Green;
        case #char "R"; return .Red;
        case #char "Y"; return .Yellow;
    }
    return .None;
}

highlight_color_to_string :: (highlightColor : HighlightColor) -> string {
    if highlightColor == {
        case .Blue; return "B";
        case .Green; return "G";
        case .Red; return "R";
        case .Yellow; return "Y";
    }
    return "";
}

highlight_color_to_vec4 :: (highlightColor : HighlightColor) -> Chamber.vec4 {
    if #complete highlightColor == {
        case .None; return .{0, 0, 0, 0};
        case .Blue; return instance.config.board.highlightColors.blue;
        case .Green; return instance.config.board.highlightColors.green;
        case .Red; return instance.config.board.highlightColors.red;
        case .Yellow; return instance.config.board.highlightColors.yellow;
    }

}

annotation_color :: (annotation : MoveAnnotation) -> Chamber.vec3 {
    if #complete annotation == {
        case .None; return instance.config.moves.mainColor;
        case .Good; return instance.config.moves.goodColor;
        case .Mistake; return instance.config.moves.mistakeColor;
        case .Brillant; return instance.config.moves.brillantColor;
        case .Blunder; return instance.config.moves.blunderColor;
        case .Interesting; return instance.config.moves.interestingColor;
        case .Dubious; return instance.config.moves.dubiousColor;
        case .Forced; return instance.config.moves.mainColor;
        case .Zugzwang; return instance.config.moves.mainColor;
    }
    return instance.config.moves.mainColor;
}

annotation_to_utf8 :: (annotation : MoveAnnotation) -> string {
    if #complete annotation == {
        case .None; return "";
        case .Good; return "!";
        case .Mistake; return "?";
        case .Brillant; return "‼";
        case .Blunder; return "⁇";
        case .Interesting; return "⁉";
        case .Dubious; return "⁈";
        case .Forced; return "□";
        case .Zugzwang; return "⨀";
    }
    return "";
}

annotation_to_utf8 :: (annotation : PositionAnnotation) -> string {
    if #complete annotation == {
        case .None; return "";
        case .Drawish; return "=";
        case .Unclear; return "∞";
        case .WhiteSlightAdvantage; return "⩲";
        case .BlackSlightAdvantage; return "⩱";
        case .WhiteModerateAdvantage; return "±";
        case .BlackModerateAdvantage; return "∓";
        case .WhiteDecisiveAdvantage; return "∔";
        case .BlackDecisiveAdvantage; return "∸";
    }
    return "";
}

annotation_to_utf8 :: (annotation : ObservationAnnotation) -> string {
    if #complete annotation == {
        case .None; return "";
        case .SpaceAdvantage; return "○";
        case .TimeAdvantage; return "↻";
        case .Initiative; return "↑";
        case .Attack; return "→";
        case .Compensation; return "≒";
        case .Counterplay; return "⇆";
        case .TimeControlPressure; return "⨁";
        case .WithIdea; return "∆";
        case .Novelty; return "ℕ";
    }
    return "";
}

move_to_algebraic :: (move : Move) -> string {
    return Basic.tprint("%1%2", coord_to_algebraic(move.sourceCoord), coord_to_algebraic(move.targetCoord));
}

get_starting_position :: () -> Position {
    position : Position;

    <<peek_piece_pointer(*position, 0, 0) = .{ .R, .White };
    <<peek_piece_pointer(*position, 0, 1) = .{ .N, .White };
    <<peek_piece_pointer(*position, 0, 2) = .{ .B, .White };
    <<peek_piece_pointer(*position, 0, 3) = .{ .Q, .White };
    <<peek_piece_pointer(*position, 0, 4) = .{ .K, .White };
    <<peek_piece_pointer(*position, 0, 5) = .{ .B, .White };
    <<peek_piece_pointer(*position, 0, 6) = .{ .N, .White };
    <<peek_piece_pointer(*position, 0, 7) = .{ .R, .White };

    for col : 0..7 {
        <<peek_piece_pointer(*position, 1, cast(u8) col) = .{ .P, .White };
        <<peek_piece_pointer(*position, 6, cast(u8) col) = .{ .P, .Black };
    }

    <<peek_piece_pointer(*position, 7, 0) = .{ .R, .Black };
    <<peek_piece_pointer(*position, 7, 1) = .{ .N, .Black };
    <<peek_piece_pointer(*position, 7, 2) = .{ .B, .Black };
    <<peek_piece_pointer(*position, 7, 3) = .{ .Q, .Black };
    <<peek_piece_pointer(*position, 7, 4) = .{ .K, .Black };
    <<peek_piece_pointer(*position, 7, 5) = .{ .B, .Black };
    <<peek_piece_pointer(*position, 7, 6) = .{ .N, .Black };
    <<peek_piece_pointer(*position, 7, 7) = .{ .R, .Black };

    position.flags |= .CastlingAllowedMask;

    return position;
}

position_is_starting_one :: (position : Position) -> bool {
    // Somewhat cheating, but maybe not that slow.
    return position_to_fen(position) == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
}

peek_piece_pointer :: (position : *Position, coord : Coord) -> *Piece {
    return *position.board[coord];
}

peek_piece_pointer :: (position : *Position, row : u8, col : u8) -> *Piece {
    return peek_piece_pointer(position, coord(row, col));
}

get_piece :: (position : Position, row : u8, col : u8) -> Piece {
    return position.board[coord(row, col)];
}

position_cleanup :: (using position : *Position) {
    Basic.free(comment);
    Basic.array_free(observationAnnotations);
    Basic.array_free(highlights.squares);
    Basic.array_free(highlights.arrows);
}

position_debug_dump :: (position : Position) {
    sb : Basic.String_Builder;
    Basic.init_string_builder(*sb);

    Basic.append(*sb, "\n");
    for row : 0..7 {
        for col : 0..7 {
            piece := get_piece(position, cast(u8) (7 - row), cast(u8) col);

            if (row + col) % 2 == 0 then Basic.append(*sb, "\e[48;5;246m");
            else Basic.append(*sb, "\e[48;5;241m");

            if piece.color == .White then Basic.append(*sb, "\e[97m");
            else Basic.append(*sb, "\e[30m");

            Basic.append(*sb, piece_to_utf8(piece));
            Basic.append(*sb, "\e[0m");
        }
        Basic.append(*sb, "\n");
    }

    Basic.log(Basic.builder_to_string(*sb));
}

position_copy_state_from :: (position : *Position, sourcePosition : Position) {
    position.board = sourcePosition.board;
    position.lastMove.sourceCoord = sourcePosition.lastMove.sourceCoord;
    position.lastMove.targetCoord = sourcePosition.lastMove.targetCoord;
    position.lastMove.capture = sourcePosition.lastMove.capture;
    position.lastMove.promotionPieceKind = sourcePosition.lastMove.promotionPieceKind;
    position.moveIndex = sourcePosition.moveIndex;
    position.movesSinceLastCaptureOrPawnMove = sourcePosition.movesSinceLastCaptureOrPawnMove;
    position.whiteClock = sourcePosition.whiteClock;
    position.blackClock = sourcePosition.blackClock;
    position.flags = sourcePosition.flags;
}

position_find_piece :: (position : Position, kind : PieceKind, color : Color) -> Coord {
    for coord : 0 .. CoordCount - 1 {
        piece := position.board[coord];
        if piece.kind == kind && piece.color == color {
            return coord;
        }
    }
    return 0xFF;
}

position_find_piece_in_direction :: (position : Position,
                                     targetCoord : Coord, rowDir : s8, colDir : s8, range : u8) -> (Piece, Coord) {
    row, col := row_col(targetCoord);

    for 1..range {
        col = cast,no_check(u8) (cast(s8) col + colDir);
        row = cast,no_check(u8) (cast(s8) row + rowDir);
        if col >= 8 || row >= 8 then break;

        testCoord := coord(row, col);
        if position.board[testCoord].kind != .None {
            return (position.board[testCoord], testCoord);
        }
    }

    return (.{ kind = .None }, 0xFF);
}

position_find_piece_in_direction :: (position : Position, piece : Piece, sourceHintCoord : Coord,
                                     targetCoord : Coord, rowDir : s8, colDir : s8, range : u8) -> Coord {
    foundPiece, foundCoord := position_find_piece_in_direction(position, targetCoord, rowDir, colDir, range);

    if !coord_same_ignoring_invalid(sourceHintCoord, foundCoord) then return 0xFF;
    if foundPiece != piece then return 0xFF;

    return foundCoord;
}

position_find_piece_source :: (position : Position, piece : Piece, sourceHintCoord : Coord, targetCoord : Coord) -> Coord {
    Basic.assert(piece.kind != .Pawn);

    for direction : PIECES_MOVEMENT[piece.kind].directions {
        sourceCoord := position_find_piece_in_direction(position, piece, sourceHintCoord, targetCoord, direction[0], direction[1], PIECES_MOVEMENT[piece.kind].range);
        if coord_is_valid(sourceCoord) then return sourceCoord;
    }

    return 0xFF;
}

position_find_piece_sources :: (position : Position, piece : Piece, sourceHintCoord : Coord, targetCoord : Coord) -> []Coord {
    Basic.assert(piece.kind != .Pawn);

    Basic.push_allocator(Basic.temp);
    sources : [..]Coord;
    for direction : PIECES_MOVEMENT[piece.kind].directions {
        sourceCoord := position_find_piece_in_direction(position, piece, sourceHintCoord, targetCoord, direction[0], direction[1], PIECES_MOVEMENT[piece.kind].range);
        if coord_is_valid(sourceCoord) {
            Basic.array_add(*sources, sourceCoord);
        }
    }

    return sources;
}

// This supposes that the input position is legal, and its flags are correct.
// The returned array is allocated on temporary storage.
position_find_piece_targets :: (position : Position, sourceCoord : Coord) -> []Coord {
    if !coord_is_valid(sourceCoord) then return .[];

    piece := position.board[sourceCoord];
    if piece.kind == .None then return .[];

    Basic.push_allocator(Basic.temp);
    targets : [..]Coord;
    pieceMovement := *PIECES_MOVEMENT[piece.kind];

    colorToPlay := piece.color;
    colorNotToPlay := ifx colorToPlay == .White then Color.Black else .White;

    row, col := row_col(sourceCoord);

    add_target_if_legal :: inline (targets : *[..]Coord, position : Position, sourceCoord : Coord, targetCoord : Coord) {
        if position_move_checkwise_legal(position, sourceCoord, targetCoord) {
            Basic.array_add(targets, targetCoord);
        }
    }

    if piece.kind == .Pawn {
        pawnDirection := ifx colorToPlay == .White then cast(s8) 1 else -1;

        // Can advance one square if empty
        advanceOneCoord := coord(cast(s8) row + pawnDirection, col);
        if position.board[advanceOneCoord].kind == .None {
            add_target_if_legal(*targets, position, sourceCoord, advanceOneCoord);

            // And can advance two squares if empty and on starting row
            pawnStartingRow := ifx colorToPlay == .White then cast(u8) 1 else 6;
            if row == pawnStartingRow {
                advanceTwoCoord := coord(cast(s8) row + 2 * pawnDirection, col);
                if position.board[advanceTwoCoord].kind == .None {
                    add_target_if_legal(*targets, position, sourceCoord, advanceTwoCoord);
                }
            }
        }

        // Can capture if an enemy piece is there or if its the en-passant coord
        enPassantCoord := position_en_passant_coord(*position);
        if col > 0 {
            captureCoord := coord(cast(s8) row + pawnDirection, col - 1);
            targetPiece := position.board[captureCoord];
            if captureCoord == enPassantCoord ||
               (targetPiece.kind != .None && targetPiece.color != colorToPlay) {
                add_target_if_legal(*targets, position, sourceCoord, captureCoord);
            }
        }
        if col < 7 {
            captureCoord := coord(cast(s8) row + pawnDirection, col + 1);
            targetPiece := position.board[captureCoord];
            if captureCoord == enPassantCoord ||
               (targetPiece.kind != .None && targetPiece.color != colorToPlay) {
                add_target_if_legal(*targets, position, sourceCoord, captureCoord);
            }
        }
    } else {
        for direction : pieceMovement.directions {
            row, col := row_col(sourceCoord);
            for 1 .. pieceMovement.range {
                col = cast,no_check(u8) (cast(s8) col + direction[1]);
                row = cast,no_check(u8) (cast(s8) row + direction[0]);
                if col >= 8 || row >= 8 then break;

                targetCoord := coord(row, col);
                if position.board[targetCoord].kind == .None {
                    add_target_if_legal(*targets, position, sourceCoord, targetCoord);
                } else if position.board[targetCoord].color == colorNotToPlay {
                    add_target_if_legal(*targets, position, sourceCoord, targetCoord);
                    break;
                } else {
                    break;
                }
            }
        }

        // Castling
        if piece.kind == .King {
            // Can't castle if in check
            if !position_square_controlled(position, sourceCoord, colorNotToPlay) {
                kingsideFlag := ifx colorToPlay == .White then PositionFlags.WhiteKingsideCastlingAllowed else .BlackKingsideCastlingAllowed;
                queensideFlag := ifx colorToPlay == .White then PositionFlags.WhiteQueensideCastlingAllowed else .BlackQueensideCastlingAllowed;
                if position.flags & kingsideFlag &&
                    position.board[coord(row, 5)].kind == .None &&
                    position.board[coord(row, 6)].kind == .None &&
                    !position_square_controlled(position, coord(row, 5), colorNotToPlay) &&
                    !position_square_controlled(position, coord(row, 6), colorNotToPlay) {
                    add_target_if_legal(*targets, position, sourceCoord, coord(row, 6));
                }
                if position.flags & queensideFlag &&
                    position.board[coord(row, 3)].kind == .None &&
                    position.board[coord(row, 2)].kind == .None &&
                    position.board[coord(row, 1)].kind == .None &&
                    !position_square_controlled(position, coord(row, 3), colorNotToPlay) &&
                    !position_square_controlled(position, coord(row, 2), colorNotToPlay) &&
                    !position_square_controlled(position, coord(row, 1), colorNotToPlay) {
                    add_target_if_legal(*targets, position, sourceCoord, coord(row, 2));
                }
            }
        }
    }


    return targets;
}

// SAN: Standard Algebraic Notation
position_last_move_to_san :: (position : Position, annotations := false) -> string {
    if position.lastMove.sourceCoord == position.lastMove.targetCoord then return "??";
    Basic.push_allocator(Basic.temp);

    piece := position.board[position.lastMove.targetCoord];
    sourceRow, sourceCol := row_col(position.lastMove.sourceCoord);
    targetRow, targetCol := row_col(position.lastMove.targetCoord);

    check := ifx position.flags & .Mate then "#" else ifx position.flags & .Check then "+" else "";
    capture := ifx position.lastMove.capture then "x" else "";

    annotationsStr : string;
    if annotations {
        annotationsStr = Basic.tprint("%", annotation_to_utf8(position.lastMove.annotation));
        annotationsStr = Basic.tprint("%1%2", annotationsStr, annotation_to_utf8(position.annotation));
        for annotation : position.observationAnnotations {
            annotationsStr = Basic.tprint("%1%2", annotationsStr, annotation_to_utf8(annotation));
        }
    }

    promotion := "";
    if position.lastMove.promotionPieceKind != .None {
        promotion = Basic.tprint("=%", piece_kind_to_symbol(piece.kind));
        piece.kind = .Pawn;
    }

    if piece.kind == .Pawn {
        sourceRow = 0xFF;
        if !position.lastMove.capture {
            sourceCol = 0xFF;
        }
    } else if piece.kind == .King {
        // Detect castling
        if targetCol == sourceCol + 2 then return Basic.tprint("O-O%1%2", check, annotationsStr);
        else if targetCol == sourceCol - 2 then return Basic.tprint("O-O-O%1%2", check, annotationsStr);

        // King is alone, never duplicated sources.
        sourceRow, sourceCol = 0xFF, 0xFF;
    } else {
        // Detect if we need to disambiguate
        duplicateSources := position_find_piece_sources(position, piece, 0xFF, position.lastMove.targetCoord);

        if duplicateSources.count == 0 {
            sourceRow, sourceCol = 0xFF, 0xFF;
        } else {
            rowConflicts, colConflicts := false, false;
            for duplicateSource : duplicateSources {
                duplicateRow, duplicateCol := row_col(duplicateSource);
                rowConflicts = rowConflicts || (duplicateRow == sourceRow);
                colConflicts = colConflicts || (duplicateCol == sourceCol);
            }

            // @note SAN prefers the col is it is sufficient to disambiguate.
            if !colConflicts then sourceRow = 0xFF;
            else if !rowConflicts then sourceCol = 0xFF;
        }
    }

    pieceStr := piece_kind_to_symbol(piece.kind);

    return Basic.tprint("%1%2%3%4%5%6%7", pieceStr, row_col_to_algebraic(sourceRow, sourceCol, silentOnInvalid = true),
                                        capture, row_col_to_algebraic(targetRow, targetCol, silentOnInvalid = true),
                                        promotion, check, annotationsStr);
}

position_move_to_san :: (position : Position, move : Move) -> string {
    Basic.push_allocator(Basic.temp);

    sanKeys := position_move_to_san_keys(position, move, true);

    text : string;
    for sanKey : sanKeys {
        if sanKey == .None then break;
        text = Basic.tprint("%1%2", text, san_key_to_symbol(sanKey));
    }

    return text;
}

position_move_to_san_keys :: (position : Position, move : Move, showActions := true) -> SanKeys {
    sanKeys : SanKeys;
    offset := 0;

    piece := position.board[move.sourceCoord];
    pieceSanKey := piece_kind_to_san_key(piece.kind);
    if pieceSanKey != .None {
        sanKeys[offset] = pieceSanKey;
        offset += 1;
    }

    capture := position.board[move.targetCoord].kind != .None ||
               (piece.kind == .Pawn && move.targetCoord == position_en_passant_coord(*position));

    sourceRow, sourceCol := row_col(move.sourceCoord);
    targetRow, targetCol := row_col(move.targetCoord);

    // Detect if we need to disambiguate
    if piece.kind == .Pawn {
        sourceRow = 0xFF;
        if !capture then sourceCol = 0xFF;
    } else if piece.kind == .King {
        // King is alone, never disambiguate sources.
        sourceRow, sourceCol = 0xFF, 0xFF;
    } else {
        duplicateSources := position_find_piece_sources(position, piece, 0xFF, move.targetCoord);

        if duplicateSources.count == 1 {
            sourceRow, sourceCol = 0xFF, 0xFF;
        } else {
            rowConflicts, colConflicts := false, false;
            for duplicateSource : duplicateSources {
                if duplicateSource == move.sourceCoord then continue;
                duplicateRow, duplicateCol := row_col(duplicateSource);
                rowConflicts = rowConflicts || (duplicateRow == sourceRow);
                colConflicts = colConflicts || (duplicateCol == sourceCol);
            }

            // @note SAN prefers the col is it is sufficient to disambiguate.
            if !colConflicts then sourceRow = 0xFF;
            else if !rowConflicts then sourceCol = 0xFF;
        }
    }

    if sourceCol != 0xFF {
        sanKeys[offset] = SanKey.ColA + cast(SanKey) sourceCol;
        offset += 1;
    }
    if sourceRow != 0xFF {
        sanKeys[offset] = SanKey.Row1 + cast(SanKey) sourceRow;
        offset += 1;
    }

    if showActions && capture {
        sanKeys[offset] = .Capture;
        offset += 1;
    }

    sanKeys[offset] = SanKey.ColA + cast(SanKey) targetCol;
    offset += 1;
    sanKeys[offset] = SanKey.Row1 + cast(SanKey) targetRow;
    offset += 1;

    if move.promotionPieceKind != .None {
        if showActions {
            sanKeys[offset] = .Promotion;
            offset += 1;
        }
        sanKeys[offset] = piece_kind_to_san_key(move.promotionPieceKind);
    }

    return sanKeys;
}

position_move_legal :: (position : *Position, sourceCoord : Coord, targetCoord : Coord, promotionPieceKind : PieceKind) -> bool {
    if sourceCoord == targetCoord || !coord_is_valid(sourceCoord) || !coord_is_valid(targetCoord) then return false;

    knownTargetCoords := position_find_piece_targets(position, sourceCoord);
    if !Basic.array_find(knownTargetCoords, targetCoord) then return false;

    // Is the promotion valid?
    targetRow, targetCol := row_col(targetCoord);
    if position.board[sourceCoord].kind == .Pawn && (targetRow == 0 || targetRow == 7) {
        if promotionPieceKind == .None || promotionPieceKind == .Pawn || promotionPieceKind == .King then return false;
    } else if promotionPieceKind != .None {
        return false;
    }

    return true;
}

position_move_checkwise_legal :: (position : Position, sourceCoord : Coord, targetCoord : Coord) -> bool {
    newPosition : Position;
    position_copy_state_from(*newPosition, position);
    position_play_move(*newPosition, sourceCoord, targetCoord, .None, updateFlags = false);

    colorToPlay := position_color_to_play(*position);
    colorNotToPlay := ifx colorToPlay == .White then Color.Black else .White;

    // Find the king(s), just being future variants proof by not stopping at the first king we met.
    for coord : 0 .. CoordCount - 1 {
        if newPosition.board[coord].kind == .King && newPosition.board[coord].color == colorToPlay {
            if position_square_controlled(*newPosition, coord, colorNotToPlay) {
                return false;
            }
        }
    }

    return true;
}

// This does not validate that the move is legal, it just plays it.
// Which may lead to illegal positions if the move is not proven legal.
position_play_move :: (position : *Position, sourceCoord : Coord, targetCoord : Coord, promotionPieceKind : PieceKind, updateFlags := true) {
    fullMoveNumber := 1 + position.moveIndex / 2;
    if !coord_is_valid(targetCoord) {
        Basic.log("%. Playing move: invalid target coord.", fullMoveNumber, flags = .ERROR);
    } else if !coord_is_valid(sourceCoord) {
        Basic.log("%. Playing to %: invalid source coord.", fullMoveNumber, coord_to_algebraic(targetCoord), flags = .ERROR);
    }

    piece := position.board[sourceCoord];
    capture := (position.board[targetCoord].kind != .None);

    position.movesSinceLastCaptureOrPawnMove += 1;
    if piece.kind == .Pawn || capture {
        position.movesSinceLastCaptureOrPawnMove = 0;
    }

    // Basic.log("%. Playing % from % to %.", fullMoveNumber, piece.kind, coord_to_algebraic(sourceCoord), coord_to_algebraic(targetCoord), flags = .VERBOSE_ONLY);

    if piece.kind == .Pawn {
        capture = !coord_same_col(sourceCoord, targetCoord);

        // En-passant, remove the captured pawn.
        if capture && position.board[targetCoord].kind == .None {
            targetRow, targetCol := row_col(targetCoord);
            enPassantCoord := coord(ifx piece.color == .White then targetRow - 1 else targetRow + 1, targetCol);
            position.board[enPassantCoord].kind = .None;
        }
    } else if piece.kind == .King {
        sourceRow, sourceCol := row_col(sourceCoord);
        targetRow, targetCol := row_col(targetCoord);
        colorToPlay := position_color_to_play(position);

        // Castling, move the rook also.
        if sourceCol == targetCol + 2 {
            position.board[coord(targetRow, 3)] = position.board[coord(sourceRow, 0)];
            position.board[coord(sourceRow, 0)].kind = .None;
            if updateFlags {
                if colorToPlay == .White then position.flags &= ~.WhiteKingsideCastlingAllowed;
                else position.flags &= ~.BlackKingsideCastlingAllowed;
            }
        } else if sourceCol == targetCol - 2 {
            position.board[coord(targetRow, 5)] = position.board[coord(sourceRow, 7)];
            position.board[coord(sourceRow, 7)].kind = .None;
            if updateFlags {
                if colorToPlay == .White then position.flags &= ~.WhiteQueensideCastlingAllowed;
                else position.flags &= ~.BlackQueensideCastlingAllowed;
            }
        }
    } else if piece.kind == .Rook && updateFlags {
        // Disable castling if the rook from its starting square
        if sourceCoord == coord(0, 0) then position.flags &= ~.WhiteQueensideCastlingAllowed;
        else if sourceCoord == coord(0, 7) then position.flags &= ~.WhiteKingsideCastlingAllowed;
        else if sourceCoord == coord(7, 0) then position.flags &= ~.BlackQueensideCastlingAllowed;
        else if sourceCoord == coord(7, 7) then position.flags &= ~.BlackKingsideCastlingAllowed;
    }

    position.moveIndex += 1;
    position.lastMove.capture = capture;
    position.lastMove.promotionPieceKind = promotionPieceKind;
    position.lastMove.sourceCoord = sourceCoord;
    position.lastMove.targetCoord = targetCoord;
    position.board[targetCoord].kind = ifx promotionPieceKind != .None then promotionPieceKind else piece.kind;
    position.board[targetCoord].color = piece.color;
    position.board[sourceCoord].kind = .None;

    if updateFlags {
        // Detect if check and/or checkmate.
        position.flags &= ~.Check;
        position.flags &= ~.Mate;

        colorNotToPlay := ifx piece.color == .White then Color.Black else .White;
        kingCoord := position_find_piece(position, .King, colorNotToPlay);
        if kingCoord != 0xFF && position_square_controlled(position, kingCoord, piece.color) {
            position.flags |= .Check;
        }

        if position_legal_moves(position, promotionVariants = false).count == 0 {
            position.flags |= ifx position.flags & .Check then PositionFlags.Mate else .StaleMate;
        }
    }
}

// Check if the specified coord is capturable by a piece of the specified color.
position_square_controlled :: (position : Position, squareCoord : Coord, color : Color) -> bool {
    if position_find_piece_source(position, make_piece(.Bishop, color), 0xFF, squareCoord) != 0xFF then return true;
    if position_find_piece_source(position, make_piece(.King, color), 0xFF, squareCoord) != 0xFF then return true;
    if position_find_piece_source(position, make_piece(.Knight, color), 0xFF, squareCoord) != 0xFF then return true;
    if position_find_piece_source(position, make_piece(.Queen, color), 0xFF, squareCoord) != 0xFF then return true;
    if position_find_piece_source(position, make_piece(.Rook, color), 0xFF, squareCoord) != 0xFF then return true;

    // Pawn captures
    pawnDirection := ifx color == .White then cast(u8) 1 else -1;
    row, col := row_col(squareCoord);
    if row - pawnDirection >= 0 && row - pawnDirection <= 7 {
        if col > 0 {
            piece := position.board[coord(row - pawnDirection, col - 1)];
            if piece.kind == .Pawn && piece.color == color return true;
        }
        if col < 7 {
            piece := position.board[coord(row - pawnDirection, col + 1)];
            if piece.kind == .Pawn && piece.color == color return true;
        }
    }

    return false;
}

// If promotionVariants is false, only one move is returned for a possible promotion,
// with the promotionPieceKind set to .None.
position_legal_moves :: (position : *Position, promotionVariants := true) -> []Move {
    Basic.push_allocator(Basic.temp);
    legalMoves : [..]Move;

    colorToPlay := position_color_to_play(position);
    for coord : 0 .. CoordCount - 1 {
        piece := position.board[coord];
        if piece.kind != .None && piece.color == colorToPlay {
            targetCoords := position_find_piece_targets(position, coord);

            move : Move;
            move.sourceCoord = coord;
            for targetCoord : targetCoords {
                move.targetCoord = targetCoord;
                targetRow, targetCol := row_col(targetCoord);

                if promotionVariants && piece.kind == .Pawn && (targetRow == 0 || targetRow == 7) {
                    // Add all promotion variants
                    for promotionPieceKind : PieceKind.[.Rook, .Knight, .Bishop, .Queen] {
                        move.promotionPieceKind = promotionPieceKind;
                        Basic.array_add(*legalMoves, move);
                    }
                } else {
                    Basic.array_add(*legalMoves, move);
                }
            }
        }
    }

    return legalMoves;
}

position_square_source_pieces :: (position : Position, squareCoord : Coord, color : Color) -> []Coord {
    Basic.push_allocator(Basic.temp);

    coords : [..]Coord;

    for coord : position_find_piece_sources(position, make_piece(.Bishop, color), 0xFF, squareCoord) {
        Basic.array_add(*coords, coord);
    }
    for coord : position_find_piece_sources(position, make_piece(.King, color), 0xFF, squareCoord) {
        Basic.array_add(*coords, coord);
    }
    for coord : position_find_piece_sources(position, make_piece(.Knight, color), 0xFF, squareCoord) {
        Basic.array_add(*coords, coord);
    }
    for coord : position_find_piece_sources(position, make_piece(.Queen, color), 0xFF, squareCoord) {
        Basic.array_add(*coords, coord);
    }
    for coord : position_find_piece_sources(position, make_piece(.Rook, color), 0xFF, squareCoord) {
        Basic.array_add(*coords, coord);
    }

    row, col := row_col(squareCoord);

    // Pawns
    pawnDirection := ifx color == .White then cast(u8) 1 else -1;
    pawnStartingRow := ifx color == .White then cast(u8) 1 else 6;
    if row != pawnStartingRow && row != pawnStartingRow - pawnDirection {
        // Advance if the target square is empty
        if position.board[squareCoord].kind == .None {
            advanceOneCoord := coord(row - pawnDirection, col);
            piece := position.board[advanceOneCoord];
            if piece.kind == .Pawn && piece.color == color {
                Basic.array_add(*coords, advanceOneCoord);
            }
            // Big advance if from the starting square and the intermediate square is empty
            if row - 2 * pawnDirection == pawnStartingRow && piece.kind == .None {
                advanceTwoCoord := coord(row - 2 * pawnDirection, col);
                piece := position.board[advanceTwoCoord];
                if piece.kind == .Pawn && piece.color == color {
                    Basic.array_add(*coords, advanceTwoCoord);
                }
            }
        }
        // Capture if the target square is not empty or en-passant
        enPassantCoord := position_en_passant_coord(*position);
        if position.board[squareCoord].kind != .None || enPassantCoord == squareCoord {
            if col > 0 {
                captureCoord := coord(row - pawnDirection, col - 1);
                piece := position.board[captureCoord];
                if piece.kind == .Pawn && piece.color == color {
                    Basic.array_add(*coords, captureCoord);
                }
            }
            if col < 7 {
                captureCoord := coord(row - pawnDirection, col + 1);
                piece := position.board[captureCoord];
                if piece.kind == .Pawn && piece.color == color {
                    Basic.array_add(*coords, captureCoord);
                }
            }
        }
    }

    // Castling
    castlingRow := ifx color == .White then 0 else 7;
    if row == castlingRow && position.board[squareCoord].kind == .None {
        kingsideFlag := ifx color == .White then PositionFlags.WhiteKingsideCastlingAllowed else .BlackKingsideCastlingAllowed;
        queensideFlag := ifx color == .White then PositionFlags.WhiteQueensideCastlingAllowed else .BlackQueensideCastlingAllowed;
        if (col == 6 && position.flags & kingsideFlag && position.board[coord(row, 5)].kind == .None) ||
           (col == 2 && position.flags & queensideFlag && position.board[coord(row, 3)].kind == .None && position.board[coord(row, 1)].kind == .None) {
            Basic.array_add(*coords, coord(row, 4));
        }
    }

    for coord : coords {
        if !position_move_checkwise_legal(position, coord, squareCoord) {
            remove coord;
        }
    }

    return coords;
}

// Removes the highlight if already existing with the same color.
// Adds it or changes its color otherwise.
position_toggle_highlight :: (position : *Position, squareHighlight : SquareHighlight) {
    defer send(.PositionHighlightsChanged, position);

    for *existingSquareHighlight : position.highlights.squares {
        if existingSquareHighlight.coord != squareHighlight.coord then continue;
        if existingSquareHighlight.color == squareHighlight.color {
            remove existingSquareHighlight;
        } else {
            existingSquareHighlight.color = squareHighlight.color;
        }
        return;
    }

    Basic.array_add(*position.highlights.squares, squareHighlight);
}

position_add_arrow_highlight :: (position : *Position, arrowHighlight : ArrowHighlight) {
    defer send(.PositionHighlightsChanged, position);

    for *existingArrowHighlight : position.highlights.arrows {
        if existingArrowHighlight.fromCoord != arrowHighlight.fromCoord then continue;
        if existingArrowHighlight.toCoord != arrowHighlight.toCoord then continue;
        if existingArrowHighlight.color == arrowHighlight.color {
            remove existingArrowHighlight;
        } else {
            existingArrowHighlight.color = arrowHighlight.color;
        }
        return;
    }

    Basic.array_add(*position.highlights.arrows, arrowHighlight);
}

position_clear_highlights :: (position : *Position) {
    position.highlights.squares.count = 0;
    position.highlights.arrows.count = 0;
    send(.PositionHighlightsChanged, position);
}

// By analyzing the last move, determine if a pawn just advanced of two squares,
// and if so return the square behind the pawn.
position_en_passant_coord :: (using position : *Position) -> Coord {
    if lastMove.targetCoord == 0xFF then return 0xFF;

    piece := board[lastMove.targetCoord];
    if piece.kind != .Pawn then return 0xFF;

    targetRow, targetCol := row_col(lastMove.targetCoord);
    sourceRow, sourceCol := row_col(lastMove.sourceCoord);
    if Math.abs(cast(s8) targetRow - cast(s8) sourceRow) != 2 then return 0xFF;

    pawnDirection := ifx position_color_to_play(position) == .White then cast(s8) -1 else 1;
    return coord(cast(s8) sourceRow + pawnDirection, targetCol);
}

position_color_to_play :: (using position : *Position) -> Color {
    return ifx moveIndex % 2 == 0 then Color.White else .Black;
}
