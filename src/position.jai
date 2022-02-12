
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
    squares : [8][8]Square;
    activeColor : Color;
    // @todo Castling en-passant etc...
}

Square :: struct {
    using piece : Piece;
}

Piece :: struct {
    using kind : PieceKind;
    color : Color;
}

// get_hash :: (piece : Piece) -> u32 {
//     Hash :: #import "Hash";
//     return Hash.get_hash(piece.kind) ^ Hash.get_hash(piece.color);
// }

// operator== :: (piece1 : Piece, piece2 : Piece) -> bool {
//     return piece1.kind == piece2.kind &&
//            piece1.color == piece2.color;
// }

PieceKind :: enum {
    Empty :: 0;
    Bishop; B :: Bishop;
    King;   K :: King;
    Knight; N :: Knight;
    Pawn;   P :: Pawn;
    Queen;  Q :: Queen;
    Rook;   R :: Rook;
}

Color :: enum {
    White :: 0;
    Black;
}

// Empty :: 0;
// WB; WK; WN; WP; WQ; WR;
// BB; BK; BN; BP; BQ; BR;
PieceId :: u8;
PieceIdCount :: 13;

get_piece_id :: (piece : Piece) -> PieceId {
    if (piece.kind == .Empty) return 0;
    return 6 * cast(u8) piece.color + cast(u8) piece.kind;
}

get_starting_position :: () -> Position {
    position : Position;

    position.squares[0][0].piece = .{ .R, .White };
    position.squares[0][1].piece = .{ .N, .White };
    position.squares[0][2].piece = .{ .B, .White };
    position.squares[0][3].piece = .{ .Q, .White };
    position.squares[0][4].piece = .{ .K, .White };
    position.squares[0][5].piece = .{ .B, .White };
    position.squares[0][6].piece = .{ .N, .White };
    position.squares[0][7].piece = .{ .R, .White };

    for 0..7 {
        position.squares[1][it].piece = .{ .P, .White };
        position.squares[6][it].piece = .{ .P, .Black };
    }

    position.squares[7][0].piece = .{ .R, .Black };
    position.squares[7][1].piece = .{ .N, .Black };
    position.squares[7][2].piece = .{ .B, .Black };
    position.squares[7][3].piece = .{ .Q, .Black };
    position.squares[7][4].piece = .{ .K, .Black };
    position.squares[7][5].piece = .{ .B, .Black };
    position.squares[7][6].piece = .{ .N, .Black };
    position.squares[7][7].piece = .{ .R, .Black };

    return position;
}
