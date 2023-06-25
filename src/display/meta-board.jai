// Holds both the boardView and extra data.
MetaBoardEntity :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;

    boardView : BoardView;
    whitePlayerName : PlayerInfoEntity;
    blackPlayerName : PlayerInfoEntity;
    whiteClock : PlayerInfoEntity;
    blackClock : PlayerInfoEntity;
    smartMover : SmartMoverEntity;

    // Used to not reupdate the text if it didn't change.
    lastWhiteStringData : *u8;
    lastBlackStringData : *u8;

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
    board_view_init(*boardView);
    smart_mover_init(*smartMover);

    Sill.entity_set_parent(*whitePlayerName, metaBoard);
    Sill.entity_set_parent(*blackPlayerName, metaBoard);
    Sill.entity_set_parent(*smartMover, metaBoard);
    Sill.entity_set_parent(*boardView, metaBoard);

    return metaBoard;
}

#scope_file

_on_message :: (using metaBoard : *MetaBoardEntity, message : *Message) {
    if message.kind == {
    case .SystemReflow;
        _reflow(metaBoard);
    case .CurrentGameChanged;
        _show(metaBoard, instance.currentGame);
    case .SelectedPlyChanged;
        _update_to_game_current_ply(metaBoard, message.newPly.game);
    }
}

_reflow :: (using metaBoard : *MetaBoardEntity) {
    // We want to fit the boardView in the left part of the screen nicely à 95% of the available space.
    eye := Magma.renderer_get_eye(engine.renderer, 0);
    size := 0.95 * Basic.min(eye.extent.width / 2.0, cast(float) eye.extent.height);
    transform.translation.x = -size / 2.0;

    board_view_update_to_size(*boardView, size);

    whitePlayerName.transform.translation.x = -size / 2;
    whitePlayerName.transform.translation.y =  size / 2 + instance.config.env.fontSize / 2 + UiConstants.PaddingVerticalSmall;
    blackPlayerName.transform.translation.x = -size / 2;
    blackPlayerName.transform.translation.y = -size / 2 - instance.config.env.fontSize / 2 - UiConstants.PaddingVerticalSmall;
    whiteClock.transform.translation.x =  size / 2;
    whiteClock.transform.translation.y =  size / 2 + instance.config.env.fontSize / 2 + UiConstants.PaddingVerticalSmall;
    blackClock.transform.translation.x =  size / 2;
    blackClock.transform.translation.y = -size / 2 - instance.config.env.fontSize / 2 - UiConstants.PaddingVerticalSmall;

    smartMover.transform.translation.y = size / 2;

    if orientation == .Black {
        whitePlayerName.transform.translation.y *= -1;
        blackPlayerName.transform.translation.y *= -1;
    }

    Sill.transform_commit(*transform);
}

_show :: (using metaBoard : *MetaBoardEntity, game : *Game) {
    Sill.entity_set_disabled(*whitePlayerName, game == null);
    Sill.entity_set_disabled(*blackPlayerName, game == null);
    Sill.entity_set_disabled(*whiteClock, game == null);
    Sill.entity_set_disabled(*blackClock, game == null);

    _reflow(metaBoard);
}

_update_to_game_current_ply :: (using metaBoard : *MetaBoardEntity, game : *Game) {
    position := *game.ply.position;
    boardOrientation := game_effective_tag(game, .BoardOrientation).color;
    board_set_position(*boardView, position);

    if boardOrientation != orientation {
        orientation = boardOrientation;
        board_view_update_from_orientation(*boardView, boardOrientation);
        _reflow(metaBoard);
    }

    _set_name :: (playerName : *PlayerInfoEntity, name : string) {
        Sill.entity_set_disabled(playerName, false);
        text_mesh_update(playerName.mesh.nodes[0].primitives[0], name, "mainBold", instance.config.env.textColor);
    }

    white := game_effective_tag(game, .White).str;
    if lastWhiteStringData != white.data {
        lastWhiteStringData = white.data;
        Sill.entity_set_disabled(*whitePlayerName, true);
        whiteElo := game_effective_tag(game, .WhiteElo).number;
        if white != "" || whiteElo != 0 {
            name := ifx whiteElo == 0 then white else Basic.tprint("% (%)", white, whiteElo);
            _set_name(*whitePlayerName, name);
        }
    }

    black := game_effective_tag(game, .Black).str;
    if lastBlackStringData != black.data {
        lastBlackStringData = black.data;
        Sill.entity_set_disabled(*blackPlayerName, true);
        blackElo := game_effective_tag(game, .BlackElo).number;
        if black != "" {
            name := ifx blackElo == 0 then black else Basic.tprint("% (%)", black, blackElo);
            _set_name(*blackPlayerName, name);
        }
    }

    Sill.entity_set_disabled(*whiteClock, true);
    if position.whiteClock.count != 0 {
        Sill.entity_set_disabled(*whiteClock, false);
        width := text_mesh_update(whiteClock.mesh.nodes[0].primitives[0], position.whiteClock, "mono", instance.config.env.textColor);
        whiteClock.mesh.nodes[0].transform.translation.x = -Math.floor(width + 0.5);
        Sill.mesh_commit_nodes(*whiteClock.mesh, instantly = true);
    }

    Sill.entity_set_disabled(*blackClock, true);
    if position.blackClock.count != 0 {
        Sill.entity_set_disabled(*blackClock, false);
        width := text_mesh_update(blackClock.mesh.nodes[0].primitives[0], position.blackClock, "mono", instance.config.env.textColor);
        blackClock.mesh.nodes[0].transform.translation.x = -Math.floor(width + 0.5);
        Sill.mesh_commit_nodes(*blackClock.mesh, instantly = true);
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
