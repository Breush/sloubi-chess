// An abstracted SAN notation.
// This is useful because the displayed move in SAN notation might be altered with language,
// this provides a way to work with a SAN notation consistantly internally.
// The one difference with SAN notation is that castling is represented by a king move to its target square.
SanKey :: enum u8 {
    None :: 0;
    Rook :: #char "R";
    Knight :: #char "N";
    Bishop :: #char "B";
    Queen :: #char "Q";
    King :: #char "K";
    Row1 :: #char "1";
    Row2 :: #char "2";
    Row3 :: #char "3";
    Row4 :: #char "4";
    Row5 :: #char "5";
    Row6 :: #char "6";
    Row7 :: #char "7";
    Row8 :: #char "8";
    ColA :: #char "a";
    ColB :: #char "b";
    ColC :: #char "c";
    ColD :: #char "d";
    ColE :: #char "e";
    ColF :: #char "f";
    ColG :: #char "g";
    ColH :: #char "h";

    // Actions, usally useless, but required by SAN.
    Capture :: #char "x";
    Promotion :: #char "=";
}

// If anything is superfluous, it is omitted.
// Piece, SourceCol, SourceRow, Capture, TargetCol, TargetRow, Promotion, PromotionPiece
SanKeys :: [8]SanKey;

san_key_to_symbol :: (sanKey : SanKey) -> string {
    if sanKey == .Rook || sanKey == .Knight || sanKey == .Bishop || sanKey == .Queen || sanKey == .King {
        return piece_kind_to_symbol(san_key_to_piece_kind(sanKey));
    }

    return Basic.tprint("%", Basic.to_string(*cast(u8) sanKey, 1));
}

san_key_to_piece_kind :: (sanKey : SanKey) -> PieceKind {
    if sanKey == {
        case .Rook; return .Rook;
        case .Knight; return .Knight;
        case .Bishop; return .Bishop;
        case .Queen; return .Queen;
        case .King; return .King;
    }
    return .None;
}

piece_kind_to_san_key :: (pieceKind : PieceKind) -> SanKey {
    if pieceKind == {
        case .Rook; return .Rook;
        case .Knight; return .Knight;
        case .Bishop; return .Bishop;
        case .Queen; return .Queen;
        case .King; return .King;
    }
    return .None;
}
