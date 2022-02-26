
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
    board : [CoordCount]Piece;

    moveIndex : u16; // @note Therefore contains the color to play: even = white, odd = black.
    lastMove : Move;

    movesSinceLastCaptureOrPawnMove : u8;

    // Extra-info about current position
    // @todo Castling rights
    check : bool;
    mate : bool;
}

Color :: enum {
    White :: 0;
    Black;
}

// @note We call "move" what litterature might call "half-move".
Move :: struct {
    sourceCoord : Coord;
    targetCoord : Coord;

    capture : bool;
    promotion : bool;
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

    return position;
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

position_find_piece_in_direction :: (position : Position,
                                     targetCoord : Coord, rowDir : s8, colDir : s8, range : u8) -> (Piece, Coord) {
    row, col := row_col(targetCoord);

    for 1..range {
        col = cast,no_check(u8) (cast(s8) col + colDir);
        row = cast,no_check(u8) (cast(s8) row + rowDir);
        if col >= 8 || row >= 8 then break;

        testCoord := coord(row, col);
        if position.board[testCoord].kind != .Empty {
            return (position.board[testCoord], testCoord);
        }
    }

    return (.{ kind = .Empty }, 0xFF);
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

    sources : [..]Coord;
    for direction : PIECES_MOVEMENT[piece.kind].directions {
        sourceCoord := position_find_piece_in_direction(position, piece, sourceHintCoord, targetCoord, direction[0], direction[1], PIECES_MOVEMENT[piece.kind].range);
        if coord_is_valid(sourceCoord) {
            Basic.array_add(*sources, sourceCoord);
        }
    }

    return sources;
}

// SAN: Standard Algebraic Notation
position_last_move_to_san :: (position : Position) -> string {
    if position.lastMove.sourceCoord == position.lastMove.targetCoord then return "??";

    piece := position.board[position.lastMove.targetCoord];
    targetRow, targetCol := row_col(position.lastMove.targetCoord);
    sourceRow, sourceCol := row_col(position.lastMove.sourceCoord);

    check := ifx position.mate then "#" else ifx position.check then "+" else "";
    capture := ifx position.lastMove.capture then "x" else "";

    promotion := "";
    if position.lastMove.promotion {
        promotion = Basic.tprint("=%", piece_to_algebraic(piece));
        piece.kind = .Pawn;
    }

    if piece.kind == .Pawn {
        sourceRow = 0xFF;
        if !position.lastMove.capture {
            sourceCol = 0xFF;
        }
    } else if piece.kind == .King {
        // Detect castling
        if targetCol == sourceCol + 2 then return Basic.tprint("O-O%", check);
        else if targetCol == sourceCol - 2 then return Basic.tprint("O-O-O%", check);

        // King is alone, never duplicated sources.
        sourceRow, sourceCol = 0xFF, 0xFF;
    } else {
        // Detect if we need to disambuigate
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

            // @note SAN prefers the col is it is sufficient to disambuigate.
            if !colConflicts then sourceRow = 0xFF;
            else if !rowConflicts then sourceCol = 0xFF;
        }
    }

    return Basic.tprint("%1%2%3%4%5%6", piece_to_algebraic(piece), row_col_to_algebraic(sourceRow, sourceCol, silentOnInvalid = true),
                                        capture, row_col_to_algebraic(targetRow, targetCol, silentOnInvalid = true),
                                        promotion, check);
}

position_play_move :: (position : *Position, sourceCoord : Coord, targetCoord : Coord, promotionPieceKind : PieceKind) {
    fullMoveNumber := 1 + position.moveIndex / 2;
    if !coord_is_valid(targetCoord) {
        Basic.log("%. Playing move: invalid target coord.", fullMoveNumber, flags = .ERROR);
    } else if !coord_is_valid(sourceCoord) {
        Basic.log("%. Playing to %: invalid source coord.", fullMoveNumber, coord_to_algebraic(targetCoord), flags = .ERROR);
    }

    piece := position.board[sourceCoord];
    capture := (position.board[targetCoord].kind != .Empty);

    // Basic.log("%. Playing % from % to %.", fullMoveNumber, piece.kind, coord_to_algebraic(sourceCoord), coord_to_algebraic(targetCoord), flags = .VERBOSE_ONLY);

    if piece.kind == .Pawn {
        capture = !coord_same_col(sourceCoord, targetCoord);

        // En-passant, remove the captured pawn.
        if capture && position.board[targetCoord].kind == .Empty {
            targetRow, targetCol := row_col(targetCoord);
            enPassantCoord := coord(ifx piece.color == .White then targetRow - 1 else targetRow + 1, targetCol);
            position.board[enPassantCoord].kind = .Empty;
        }
    } else if piece.kind == .King {
        sourceRow, sourceCol := row_col(sourceCoord);
        targetRow, targetCol := row_col(targetCoord);

        // Castling, move the rook also.
        if sourceCol == targetCol + 2 {
            position.board[coord(targetRow, 3)] = position.board[coord(sourceRow, 0)];
            position.board[coord(sourceRow, 0)].kind = .Empty;
        } else if sourceCol == targetCol - 2 {
            position.board[coord(targetRow, 5)] = position.board[coord(sourceRow, 7)];
            position.board[coord(sourceRow, 7)].kind = .Empty;
        }
    }

    position.moveIndex += 1;
    position.lastMove.capture = capture;
    position.lastMove.promotion = (promotionPieceKind != .Empty);
    position.lastMove.sourceCoord = sourceCoord;
    position.lastMove.targetCoord = targetCoord;
    position.board[targetCoord].kind = ifx promotionPieceKind != .Empty then promotionPieceKind else piece.kind;
    position.board[targetCoord].color = piece.color;
    position.board[sourceCoord].kind = .Empty;

    // @todo :AutoCheck Detect if check, checkmate automatically!
}
