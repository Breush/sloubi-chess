// Holds both the board and extra data.
MetaBoardEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;

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

meta_board_create :: () -> *MetaBoardEntity {
    using metaBoard := SillMeta.create_meta_board_entity(instance.engine);
    Sill.listener_on_message(*listener, _on_message);
    _init_meshes(metaBoard);
    board_init(*board);

    Sill.entity_set_parent(*whitePlayerName, metaBoard);
    Sill.entity_set_parent(*blackPlayerName, metaBoard);
    Sill.entity_set_parent(*board, metaBoard);

    return metaBoard;
}

#scope_file

_on_message :: (using metaBoard : *MetaBoardEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _reflow(metaBoard);
    case .ModeGameStarted;
        _show(metaBoard, instance.game);
    case .GameSelectedPlyChanged;
        _update_to_position(metaBoard, *instance.game.ply.position);
    }
}

_reflow :: (using metaBoard : *MetaBoardEntity) {
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

_show :: (using metaBoard : *MetaBoardEntity, game : Game) {
    Sill.entity_set_disabled(*whitePlayerName, true);
    Sill.entity_set_disabled(*blackPlayerName, true);

    _set_name :: (playerName : *PlayerInfoEntity, name : string) {
        Sill.entity_set_disabled(playerName, false);
        charInfos := text_mesh_update(playerName.mesh.nodes[0].primitives[0], name, "mainBold", instance.config.env.textColor);
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

    orientation = game.boardOrientation;

    board_update_from_orientation(*board, orientation);
    _reflow(metaBoard);
}

_update_to_position :: (using metaBoard : *MetaBoardEntity, position : *Position) {
    board_state_set_position(*board, position);

    Sill.entity_set_disabled(*whiteClock, true);
    if position.whiteClock.count != 0 {
        Sill.entity_set_disabled(*whiteClock, false);
        charInfos := text_mesh_update(whiteClock.mesh.nodes[0].primitives[0], position.whiteClock, "mono", instance.config.env.textColor);
        whiteClock.mesh.nodes[0].transform.translation.x = -Basic.peek(charInfos).effective.xStart - Basic.peek(charInfos).glyphAdvance;
        Basic.array_free(charInfos);
    }

    Sill.entity_set_disabled(*blackClock, true);
    if position.blackClock.count != 0 {
        Sill.entity_set_disabled(*blackClock, false);
        charInfos := text_mesh_update(blackClock.mesh.nodes[0].primitives[0], position.blackClock, "mono", instance.config.env.textColor);
        blackClock.mesh.nodes[0].transform.translation.x = -Basic.peek(charInfos).effective.xStart - Basic.peek(charInfos).glyphAdvance;
        Basic.array_free(charInfos);
    }

    instance.metaBoard.moveIndex = position.moveIndex;
}

_init_meshes :: (using metaBoard : *MetaBoardEntity) {
    init_player_info :: (metaBoard : *MetaBoardEntity, entity : *PlayerInfoEntity) {
        Sill.entity_set_parent(entity, metaBoard);
        Basic.array_add(*entity.mesh.nodes, .{});
        Basic.array_add(*entity.mesh.nodes[0].primitives, create_text_mesh());
        entity.mesh.nodes[0].transform.translation.y -= instance.config.env.fontSize / 2;
        entity.mesh.nodes[0].transform.translation.z = -0.2;
    }

    init_player_info(metaBoard, *whitePlayerName);
    init_player_info(metaBoard, *blackPlayerName);
    init_player_info(metaBoard, *whiteClock);
    init_player_info(metaBoard, *blackClock);
}
