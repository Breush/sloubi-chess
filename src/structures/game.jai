/* A "Game" can be understood as a collections of variations starting from one position. */
Game :: struct {
    study : *Study; @NoSerialize
    view : *GameView; @NoSerialize

    mainVariation : *VariationEntity; @NoSerialize
    ply : *PlyEntity; @NoSerialize // Selected ply.

    // -- User-level configurable data
    title : string;
    // @note Tags are somewhat understood by SloubiChess, and can be overwritten
    // within a position. For instance, in PGN, we can write {[%tag BoardOrientation,White]}
    // to change the board orientation as we reach this position.
    tags : [TagName.Count]TagValue; @NoSerialize
    extraTags : [..]struct { name : string; value : string; }; @NoSerialize

    // -- Cache
    bytes : string; @NoSerialize // View from the bytes array in study, showing one game in PGN format.
    summary : GameSummary;
    computeFlags : ComputeFlags;
    snapshots : [..]string; @NoSerialize

    ComputeFlags :: enum_flags u8 {
        Summary;    // summary is valid
        Plies;      // mainVariation is valid
    }
}

GameSummary :: struct {
    lastBoardPosition : CompactBoardPosition;
    lastMove : SimpleMove;
    lastBoardOrientation : Color;
}

TagName :: enum u8 {
    // PGN standard tags.
    Event;              // str
    Site;               // str
    Date;               // str
    Round;              // str
    White;              // str @todo At the end, map to one player in a database.
    Black;              // str
    LastStrTag :: Black;

    // Result; // :ResultInPosition

    // PGN non-standard tags.
    WhiteElo;           // number
    BlackElo;           // number
    LastNumberTag :: BlackElo;

    BoardOrientation;   // color
    LastColorTag :: BoardOrientation;
    Count; // Not a real value, keep last.
}

TagValue :: union {
    str : string;
    number : u32;
    color : Color;
}

load_game :: (filename : string, gameIndex : u32, computeFlags := Game.ComputeFlags.Plies) -> *Game {
    study := load_study(filename);

    // @note We try not to load the GamesBytes if we don't need to,
    // therefore we just look as if the study exists and has a valid summary for the game first.
    if study == null then return null;
    if study.games.count > gameIndex && study.games[gameIndex].computeFlags & computeFlags then return *study.games[gameIndex];

    game : *Game;
    if study.games.count > gameIndex then game = *study.games[gameIndex];

    // Load the bytes and the PGN only if the game is not already in memory.
    if game == null || game.mainVariation == null {
        study = load_study(filename, .GamesBytes);
        if study == null || study.games.count <= gameIndex then return null;
        game = *study.games[gameIndex];
        load_pgn(game.bytes, game);
        game.computeFlags |= .Plies;
    }

    if computeFlags == 0 || game.computeFlags & computeFlags then return game;

    if computeFlags & .Summary && !(game.computeFlags & .Summary) {
        _load_game_summary(game);
    }

    return game;
}

game_create :: (game : *Game) {
    if game.mainVariation == null {
        load_pgn(game.bytes, game);
        game.computeFlags |= .Plies;
    }

    game_view_init(game);
    game_show(game);
    game_update_to(game, game.mainVariation.plies[0]);
    game_add_snapshot(game);
}

game_close :: (game : *Game) {
    if game == null || game.mainVariation == null then return;

    variation_cleanup(game.mainVariation);
    game.mainVariation = null;

    if game.view != null {
        Sill.destroy_entity(game.view);
        game.view = null;
    }

    if instance.currentGame == game then game_show(null);
}

game_cleanup :: (game : *Game) {
    if game == null then return;

    game_reset(game);
    Basic.free(game.title);

    if game.view != null {
        Sill.destroy_entity(game.view);
        game.view = null;
    }

    game_show(null);
}

game_reset :: (game : *Game) {
    if game == null then return;

    if game.mainVariation != null {
        variation_cleanup(game.mainVariation);
        game.mainVariation = null;
    }

    Basic.free(game.tags[TagName.Event].str);
    Basic.free(game.tags[TagName.Site].str);
    Basic.free(game.tags[TagName.Date].str);
    Basic.free(game.tags[TagName.Round].str);
    Basic.free(game.tags[TagName.White].str);
    Basic.free(game.tags[TagName.Black].str);
    for extraTag : game.extraTags {
        Basic.free(extraTag.name);
        Basic.free(extraTag.value);
    }
    Basic.array_free(game.extraTags);
}

game_show :: (game : *Game) {
    if (instance.currentGame == game) return;
    instance.currentGame = game;
    send(.CurrentGameChanged, game);
}

game_add_snapshot :: (game : *Game) {
    // @todo It would be better to have a dedicated serialization than the PGN one.
    // But this will do for now.
    // @fixme Handle adding a snapshot in the middle.

    sb : Basic.String_Builder;
    Basic.init_string_builder(*sb);
    defer Basic.reset(*sb);
    write_pgn(*sb, game);
    Basic.array_add(*game.snapshots, Basic.builder_to_string(*sb));
}

// @fixme Handle redo.
game_undo :: (game : *Game) {
    // @fixme Uber-stupid for now, but it does the job.
    // @fixme Will need to try to rematch to the previously selected move.

    if game.snapshots.count < 2 then return;

    snapshot := game.snapshots[game.snapshots.count - 2];

    game_reset(game);
    load_pgn(snapshot, game);

    Basic.free(game.snapshots[game.snapshots.count - 1]);
    game.snapshots.count -= 1;

    variation_init(game.mainVariation, game);
    game_update_to(game, game.mainVariation.plies[game.mainVariation.plies.count - 1]);
    ply_place(game.ply, propagate = true);
}

game_setup_main_variation :: (game : *Game) {
    game.mainVariation = SillMeta.create_variation_entity(instance.engine);
}

game_add_variation :: (game : *Game, parentPly : *PlyEntity) -> *VariationEntity {
    variation := SillMeta.create_variation_entity(instance.engine);
    variation.collapsed = instance.config.moves.variationsCollapsed;
    Basic.array_add(*parentPly.variations, variation);

    variation.parentPly = parentPly;
    variation.index = cast(u16) (parentPly.variations.count - 1);
    variation.depth = parentPly.parentVariation.depth + 1;
    return variation;
}

game_add_subgame :: (game : *Game) {
    ply := variation_add_ply(game.mainVariation);
    ply.position = get_starting_position();
    ply.position.comment = String.copy_string("[Subgame]");
    ply.first = true;

    ply_init(ply, game);
    ply_place(ply, propagate = true);
    game_update_to(game, ply);;
}

game_refresh_backlinks :: (game : *Game) {
    if game.view == null then return;
    game.view.game = game;
    variation_refresh_backlinks(game.mainVariation, game);
}

game_update_to :: (game : *Game, ply : *PlyEntity) {
    oldPly := game.ply;
    game.ply = ply;

    send(.SelectedPlyChanged, game.ply, oldPly);
}

game_go_to_first_ply :: (game : *Game) {
    game_update_to(game, game.ply.parentVariation.plies[0]);
}

game_go_to_last_ply :: (game : *Game) {
    game_update_to(game, Basic.peek(game.ply.parentVariation.plies));
}

game_go_to_previous_move :: (game : *Game) {
    variation := game.ply.parentVariation;

    if game.ply.index == 0 {
        if game.ply.parentVariation == game.mainVariation then return;
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
           (nextPly.position.lastMove.promotionPieceKind == promotionPieceKind) {
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
        basePly := variation_add_ply(variation);
        position_copy_state_from(*basePly.position, game.ply.position);
        variation_init(variation, game);
    }

    ply := variation_add_ply(variation);
    position_copy_state_from(*ply.position, game.ply.position);
    position_play_move(*ply.position, sourceCoord, targetCoord, promotionPieceKind);

    if nextPly == null {
        game.ply.position.result = .None;
        send(.PlyResultChanged, game.ply);
    }

    ply_init(ply, game);
    ply_place(ply, propagate = true);
    game_update_to(game, ply);

    // @todo :StudyDirty Technically, it would be better to send a message.
    study_mark_unsaved_modifications(game.study);
    game_add_snapshot(game);
}

game_edit_ply_comment :: (game : *Game) {
    if game.ply == null then return;
    ply_edit_comment(game.ply);
}

game_delete_ply :: (game : *Game) {
    if game.ply == null then return;
    previousPly := ply_delete(game.ply);

    if previousPly {
        ply_place(previousPly, propagate = true);
        game_update_to(game, previousPly);
    }

    // :StudyDirty
    study_mark_unsaved_modifications(game.study);
    game_add_snapshot(game);
}

game_effective_tag :: (game : *Game, tagName : TagName) -> *TagValue {
    return game_ply_effective_tag(game, game.ply, tagName);
}

game_ply_effective_tag :: (game : *Game, ply : *PlyEntity, tagName : TagName) -> *TagValue {
    tagValue : *TagValue;
    if ply != null then tagValue = ply_effective_tag(ply, tagName);
    return ifx tagValue != null then tagValue else *game.tags[tagName];
}

game_subgame_tag_or_empty :: (game : *Game, subgameFirstPly : *PlyEntity, tagName : TagName) -> TagValue {
    if subgameFirstPly == game.mainVariation.plies[0] {
        return game.tags[tagName];
    }

    tagValue := Hash.table_find_pointer(*subgameFirstPly.position.tags, tagName);
    if tagValue != null then return tagValue.*;
    return .{};
}

game_subgame_set_tag :: (game : *Game, subgameFirstPly : *PlyEntity, tagName : TagName, tagValue : TagValue) {
    if subgameFirstPly == game.mainVariation.plies[0] {
        if tagName <= .LastStrTag then Basic.free(game.tags[tagName].str);
        game.tags[tagName] = tagValue;
        return;
    }

    existingTagValue := Hash.table_find_pointer(*subgameFirstPly.position.tags, tagName);
    if existingTagValue != null {
        if tagName <= .LastStrTag then Basic.free(existingTagValue.str);
        existingTagValue.* = tagValue;
    } else {
        Hash.table_add(*subgameFirstPly.position.tags, tagName, tagValue);
    }
}

game_subgame_first_ply :: (game : *Game) -> *PlyEntity {
    if game.ply == null then return null;
    return ply_subgame_first_ply(game.ply);
}

game_debug_dump :: (game : Game) {
    variation_debug_dump(game.mainVariation, 0);
}

#scope_file

_load_game_summary :: (game : *Game) {
    game.computeFlags |= .Summary;
    lastPly := Basic.peek(game.mainVariation.plies);
    game.summary.lastBoardPosition = compact_board_position(lastPly.position.board);
    game.summary.lastMove = lastPly.position.lastMove.simpleMove; // @todo Compiler bug, .simpleMove should not be needed.
    game.summary.lastBoardOrientation = game_ply_effective_tag(game, lastPly, .BoardOrientation).color;
}
