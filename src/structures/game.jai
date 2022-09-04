/* A "Game" can be understood as a collections of variations starting from one position. */
Game :: struct {
    mainVariation : Variation;

    boardOrientation : Color;
    result : Result;
    pgnFileName : string;
    tags : struct {
        // PGN standard tags, except Result.
        event : string;
        site : string;
        date : string;
        round : string;
        white : string; // @todo At the end, map to one player in a database.
        black : string;
        // PGN non-standard tags.
        whiteElo : u16;
        blackElo : u16;

        // Other tags, not used internally. @note Not a hash-table to keep order.
        extra : [..]struct { name : string; value : string; };
    }

    ply : *PlyEntity; // Current ply displayed.

    // @note In order to never invalidate pointers but still
    // have efficient memory layout, we use pools.
    variationPool : Bucket_Array.Bucket_Array(Variation, 32);

    Result :: enum {
        Unknown :: 0;
        WhiteWin;
        BlackWin;
        Draw;
    }
}

Variation :: struct {
    // @note plies[0].position is the initial position.
    // And it should not get any variation in it.
    plies : [..]*PlyEntity; // @note Do not flatten this, the struct might be needed for extra info about a variation.

    parentPly : *PlyEntity; // Can be null for the main variation.
    index : u16; // Index of the variation in the parent ply.

    depth : u16;
    collapsed : bool;
}

game_show :: (game : *Game) {
    meta_board_show(game);
    list_show(game);
    button_bar_show();

    game_update_to(game, game.mainVariation.plies[0]);
}

game_cleanup :: (game : *Game) {
    game.ply = null;
    variation_cleanup(*game.mainVariation);

    Bucket_Array.bucket_array_reset(*game.variationPool);

    Basic.free(game.pgnFileName);

    (<<game) = .{};
}

variation_cleanup :: (variation : *Variation) {
    for ply : variation.plies {
        ply_cleanup(ply);
    }
    Basic.array_free(variation.plies);
}

// @fixme Move all that on_cleanup?
ply_cleanup :: (ply : *PlyEntity) {
    for variation : ply.variations {
        variation_cleanup(variation);
    }
    Basic.array_free(ply.variations);

    Sill.destroy_entity(ply);
}

game_add_variation :: (game : *Game, parentPly : *PlyEntity) -> *Variation {
    variation := Bucket_Array.find_and_occupy_empty_slot(*game.variationPool);
    variation.collapsed = instance.config.moves.variationsCollapsed;
    Basic.array_add(*parentPly.variations, variation);

    variation.parentPly = parentPly;
    variation.index = cast(u16) (parentPly.variations.count - 1);
    variation.depth = parentPly.parentVariation.depth + 1;
    return variation;
}

game_add_variation_ply :: (game : *Game, parentVariation : *Variation) -> *PlyEntity {
    ply := SillMeta.create_ply_entity(instance.engine);
    Basic.array_add(*parentVariation.plies, ply);

    ply.parentVariation = parentVariation;
    ply.index = cast(u16) (parentVariation.plies.count - 1);
    return ply;
}

game_update_to :: (game : *Game, ply : *PlyEntity) {
    oldPly := game.ply;
    game.ply = ply;

    variation := game_current_variation(game);
    meta_board_orient(game.boardOrientation);
    meta_board_update_to_position(ply.position);
    list_update_to_current_move(game, oldPly);
}

game_current_variation :: (game : *Game) -> *Variation {
    return game.ply.parentVariation;
}

game_go_to_first_ply :: (game : *Game) {
    game_update_to(game, game.ply.parentVariation.plies[0]);
}

game_go_to_last_ply :: (game : *Game) {
    game_update_to(game, Basic.peek(game.ply.parentVariation.plies));
}

game_go_to_previous_move :: (game : *Game) {
    variation := game_current_variation(game);

    if game.ply.index == 0 {
        if game.ply.parentVariation == *game.mainVariation then return;
        game_go_to_previous_variation(game);
        game_go_to_previous_move(game);
        game_go_to_previous_move(game);
        return;
    }

    game_update_to(game, game.ply.parentVariation.plies[game.ply.index - 1]);
}

game_go_to_next_move :: (game : *Game) {
    if game.ply.index == game.ply.parentVariation.plies.count - 1 then return;
    game_update_to(game, game.ply.parentVariation.plies[game.ply.index + 1]);
}

game_go_to_previous_variation :: (game : *Game) {
    variation := game.ply.parentVariation;
    variationParentPly := variation.parentPly;
    if variationParentPly != null {
        if variation.index > 0 {
            game_update_to(game, variationParentPly.variations[variation.index - 1].plies[1]);
        } else {
            game_update_to(game, variationParentPly);
        }
    }
}

game_go_to_next_variation :: (game : *Game) {
    // Is there a subvariation from where we are?
    if game.ply.variations.count != 0 {
        game_update_to(game, game.ply.variations[0].plies[1]);
    }
    // Or is there a next variation in the parent one?
    else {
        variation := game.ply.parentVariation;
        variationParentPly := game.ply.parentVariation.parentPly;
        if variationParentPly != null {
            if variation.index < variationParentPly.variations.count - 1 {
                game_update_to(game, variationParentPly.variations[variation.index + 1].plies[1]);
            }
        }
    }
}

game_play_move :: (game : *Game, sourceCoord : Coord, targetCoord : Coord, promotionPieceKind : PieceKind) {
    // Check if the move already exists, and if so, just select it
    for nextPly : ply_next_plies(game.ply) {
        if nextPly.position.lastMove.sourceCoord == sourceCoord &&
           nextPly.position.lastMove.targetCoord == targetCoord &&
           (!nextPly.position.lastMove.promotion || nextPly.position.board[targetCoord].kind == promotionPieceKind) {
            game_update_to(game, nextPly);
            return;
        }
    }

    // The position does not exists yet, so:
    //  - if a next ply already exists, create a new variation
    //  - if there's no next ply, add to the current variation
    variation := game.ply.parentVariation;
    nextPly := ply_next_ply(game.ply);
    if nextPly != null {
        variation = game_add_variation(game, nextPly);
        basePly := game_add_variation_ply(game, variation); // @todo Better to just store the starting position within the variation?
        position_copy_state_from(*basePly.position, game.ply.position);
        ply_init(basePly);
    }

    ply := game_add_variation_ply(game, variation);
    position_copy_state_from(*ply.position, game.ply.position);
    position_play_move(*ply.position, sourceCoord, targetCoord, promotionPieceKind);

    ply_init(ply);
    game_update_to(game, ply);
}

game_edit_ply_comment :: (game : *Game) {
    if game.ply == null then return;
    ply_edit_comment(game.ply);
}

game_result_to_string :: (result : Game.Result) -> string {
    if #complete result == {
        case .Unknown; return "*";
        case .WhiteWin; return "1-0";
        case .BlackWin; return "0-1";
        case .Draw; return "1/2-1/2";
    }
}

game_debug_dump :: (game : Game) {
    variation_debug_dump(game.mainVariation, 0);
}

piece_at_coord :: (coord : Coord) -> Piece {
    if instance.game.ply == null then return .{}; // Empty
    return instance.game.ply.position.board[coord];
}

variation_collapse :: (variation : *Variation) {
    variation.collapsed = !variation.collapsed;
    replace_ply_recursively(variation.plies[0]);
}

variation_debug_dump :: (variation : Variation, depth : u8) {
    prefix := "| | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | ";
    prefix.count = depth * 2;

    for ply, plyIndex : variation.plies {
        if plyIndex == 0 {
            prefix.count -= 1;
            Chamber.debug(prefix, "> {", ply.position.comment, "}");
            prefix.count += 1;
        } else {
            fullMoveIndex := (ply.position.moveIndex + 1) / 2;
            Chamber.debug(prefix, fullMoveIndex, ifx ply.position.moveIndex % 2 then ". " else "… ", position_last_move_to_san(ply.position), " {", ply.position.comment, "}");
        }

        for variation : ply.variations {
            variation_debug_dump(<<variation, depth + 1);
        }
    }
}

ply_previous_ply :: (ply : *PlyEntity) -> *PlyEntity {
    if ply.index == 0 {
        parentPly := ply.parentVariation.parentPly;
        if parentPly == null || parentPly.index < 2 then return null;
        return parentPly.parentVariation.plies[parentPly.index - 2];
    }
    return ply.parentVariation.plies[ply.index - 1];
}

ply_next_ply :: (ply : *PlyEntity) -> *PlyEntity {
    if ply.index == ply.parentVariation.plies.count - 1 then return null;

    // If we're the first ply in our variation, we're not real,
    // so better get the real ply!
    if ply.index == 0 && ply.parentVariation.parentPly != null {
        return ply.parentVariation.parentPly;
    }

    return ply.parentVariation.plies[ply.index + 1];
}

// List of all plies after this one that already exist in the current game.
ply_next_plies :: (ply : *PlyEntity) -> []*PlyEntity {
    nextPly := ply_next_ply(ply);
    if nextPly == null then return .[];

    Basic.push_allocator(Basic.temp);
    nextPlies : [..]*PlyEntity;

    Basic.array_add(*nextPlies, nextPly);
    for nextPlyVariation : nextPly.variations {
        Basic.array_add(*nextPlies, nextPlyVariation.plies[1]);
    }

    return nextPlies;
}
