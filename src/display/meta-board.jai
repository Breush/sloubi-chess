// Holds both the board and extra data.
MetaBoardEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;

    board : BoardEntity;
    whitePlayerName : PlayerInfoEntity;
    blackPlayerName : PlayerInfoEntity;
    whiteClock : PlayerInfoEntity;
    blackClock : PlayerInfoEntity;

    orientation : Color;
    moveIndex : u16;
}

PlayerInfoEntity :: struct {
    using #as entity : Sill.Entity; @Sill:NoStorage

    transform : Sill.TransformComponent;
    mesh : Sill.MeshComponent;
}

meta_board_init :: () {
    using instance.metaBoard;

    instance.metaBoard = SillMeta.create_meta_board_entity(instance.engine);
    _init_meshes();
    board_init(*board);

    Sill.entity_set_parent(*whitePlayerName, instance.metaBoard);
    Sill.entity_set_parent(*blackPlayerName, instance.metaBoard);
    Sill.entity_set_parent(*board, instance.metaBoard);
    meta_board_reflow();
}

meta_board_show :: (game : Game) {
    using instance.metaBoard;

    whitePlayerName.mesh.nodes[0].primitives[0].disabled = true;
    blackPlayerName.mesh.nodes[0].primitives[0].disabled = true;

    _set_name :: (playerInfoEntity : *PlayerInfoEntity, name : string) {
        playerInfoEntity.mesh.nodes[0].primitives[0].disabled = false;
        charInfos := text_mesh_update(playerInfoEntity.mesh.nodes[0].primitives[0], name, "mainBold", instance.config.env.textColor);
        Basic.array_free(charInfos);

    }

    if game.tags.white != "" {
        name := ifx game.tags.whiteElo == 0 then game.tags.white
                                            else Basic.tprint("% (%)", game.tags.white, game.tags.whiteElo);
        _set_name(*whitePlayerName, name);
    }

    if game.tags.black != "" {
        name := ifx game.tags.blackElo == 0 then game.tags.black
                                            else Basic.tprint("% (%)", game.tags.black, game.tags.blackElo);
        _set_name(*blackPlayerName, name);
    }

    meta_board_reflow();
}

meta_board_reflow :: () {
    using instance.metaBoard;

    // We want to fit the board in the left part of the screen nicely à 95% of the available space.
    eye := Magma.renderer_get_eye(engine.renderer, 0);
    size := 0.95 * Basic.min(eye.extent.width / 2.0, cast(float) eye.extent.height);
    transform.translation.x = -size / 2.0;

    board_update_to_size(*board, size);

    whitePlayerName.transform.translation.x = -size / 2;
    whitePlayerName.transform.translation.y =  size / 2 + instance.config.env.fontSize / 2 + UiConstants.PaddingPlayerName;
    blackPlayerName.transform.translation.x = -size / 2;
    blackPlayerName.transform.translation.y = -size / 2 - instance.config.env.fontSize / 2 - UiConstants.PaddingPlayerName;
    whiteClock.transform.translation.x =  size / 2;
    whiteClock.transform.translation.y =  size / 2 + instance.config.env.fontSize / 2 + UiConstants.PaddingPlayerName;
    blackClock.transform.translation.x =  size / 2;
    blackClock.transform.translation.y = -size / 2 - instance.config.env.fontSize / 2 - UiConstants.PaddingPlayerName;

    if orientation == .Black {
        whitePlayerName.transform.translation.y *= -1;
        blackPlayerName.transform.translation.y *= -1;
    }

    Sill.transform_commit(*transform);
}

meta_board_orient :: (_orientation : Color) {
    using instance.metaBoard;
    orientation = _orientation;

    board_update_from_orientation(*board, orientation);
    meta_board_reflow();
}

meta_board_update_to_position :: (position : Position) {
    using instance.metaBoard;

    board_update_to_position(*board, position);

    whiteClock.mesh.nodes[0].primitives[0].disabled = true;
    if position.whiteClock.count != 0 {
        whiteClock.mesh.nodes[0].primitives[0].disabled = false;
        charInfos := text_mesh_update(whiteClock.mesh.nodes[0].primitives[0], position.whiteClock, "mono", instance.config.env.textColor);
        whiteClock.mesh.nodes[0].transform.translation.x = -Basic.peek(charInfos).effective.xStart - Basic.peek(charInfos).glyphAdvance;
        Basic.array_free(charInfos);
    }

    blackClock.mesh.nodes[0].primitives[0].disabled = true;
    if position.blackClock.count != 0 {
        blackClock.mesh.nodes[0].primitives[0].disabled = false;
        charInfos := text_mesh_update(blackClock.mesh.nodes[0].primitives[0], position.blackClock, "mono", instance.config.env.textColor);
        blackClock.mesh.nodes[0].transform.translation.x = -Basic.peek(charInfos).effective.xStart - Basic.peek(charInfos).glyphAdvance;
        Basic.array_free(charInfos);
    }

    instance.metaBoard.moveIndex = position.moveIndex;
}

#scope_file

_init_meshes :: () {
    using instance.metaBoard;

    init_player_info :: (entity : *PlayerInfoEntity) {
        Sill.entity_set_parent(entity, instance.metaBoard);
        Basic.array_add(*entity.mesh.nodes, .{});
        Basic.array_add(*entity.mesh.nodes[0].primitives, create_text_mesh());
        entity.mesh.nodes[0].transform.translation.y -= instance.config.env.fontSize / 2;
        entity.mesh.nodes[0].transform.translation.z = -0.2;
    }

    init_player_info(*whitePlayerName);
    init_player_info(*blackPlayerName);
    init_player_info(*whiteClock);
    init_player_info(*blackClock);
}
