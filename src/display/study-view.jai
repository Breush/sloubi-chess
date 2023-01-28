StudyView :: struct {
    using #as entity : Sill.Entity;

    transform : Sill.TransformComponent;
    listener : Sill.ListenerComponent;
    ui : Sill.UiComponent;
    tab : TabComponent;

    study : *Study;
}

study_view_create :: (study : *Study) -> *StudyView {
    studyView := SillMeta.create_study_view_entity(instance.engine);
    Sill.listener_on_message(*studyView.listener, _on_message);
    studyView.study = study;

    studyView.tab.text = study.title;
    studyView.tab.icon = ifx study.infoFlags & .MultipleGames then ForkAwesome.Book else ForkAwesome.Gamepad;
    studyView.tab.onReflow = xx _on_reflow;
    Basic.array_add(*studyView.tab.actions, .{ "Close study", ForkAwesome.WindowCloseO, xx _on_close, .Right });
    Basic.array_add(*studyView.tab.actions, .{ "Save as PGN", ForkAwesome.FloppyO, xx _on_save, .None });
    Basic.array_add(*studyView.tab.actions, .{ "Open external analysis", ForkAwesome.Laptop, xx _on_open_external_analysis, .Right });
    Basic.array_add(*studyView.tab.actions, .{ "Create new game", ForkAwesome.Plus, xx _on_create_new_game, .Left });
    tab_commit_text(*studyView.tab);
    tab_commit_actions(*studyView.tab);

    studyView.tab.menu.onItemClick = xx _on_menu_item_click;
    _refresh_games_list(studyView);
    _on_reflow(studyView);

    Sill.transform_commit(*studyView.transform);

    return studyView;
}

#scope_file

_on_message :: (using studyView : *StudyView, message : *Message) {
    if message.kind == {
    case .StudyCurrentGameChanged;
        if study == message.study {
            for *game, gameIndex : study.games {
                if game == study.currentGame then tab.menu.selectedItemIndex = cast(u32) gameIndex;
            }
            for *game, gameIndex : study.temporaryGames {
                if game == study.currentGame then tab.menu.selectedItemIndex = cast(u32) (study.games.count + gameIndex);
            }
            tab_commit_menu(*tab);
        }
    case .StudyGamesChanged;
        if study == message.study {
            _refresh_games_list(studyView);
        }
    case .StudyUnsavedModificationsChanged;
        if study == message.study {
            tab.actions[1].place = ifx study.hasUnsavedModifications then TabComponent.Action.Place.Right else .None;
            tab_commit_actions(*tab);
        }
    }
}

_on_reflow :: (using studyView : *StudyView) {
    for *game : study.games {
        if game.view == null then continue;
        game_view_reflow(game.view);
    }
}

_refresh_games_list :: (using studyView : *StudyView) {
    Basic.array_resize(*tab.menu.items, study.games.count + study.temporaryGames.count);
    for *game, gameIndex : study.games {
        tab.menu.items[gameIndex] = game.title;
    }
    for *game, gameIndex : study.temporaryGames {
        tab.menu.items[study.games.count + gameIndex] = game.title;
    }
    tab_commit_menu(*tab);
}

_on_menu_item_click :: (using studyView : *StudyView, itemIndex : u32) {
    if itemIndex >= study.games.count {
        study_show_game(study, *study.temporaryGames[itemIndex - study.games.count]);
    } else {
        study_show_game(study, *study.games[itemIndex]);
    }
}

_on_create_new_game :: (using studyView : *StudyView) {
    study_add_game(study);
}

_on_close :: (using studyView : *StudyView) {
    if study.hasUnsavedModifications {
        dialog_create("Do you want to save the changes you made to this study?",
                      "Your changes will be lost if you don't save them.",
                      .["Save", "Cancel", "Don't save"],
                      (dialog : *DialogEntity, choiceIndex : u32, study : *Study) {
            dialog_close(dialog);

            if choiceIndex == 0 {
                study_save(study);
                study_close(study);
            } else if choiceIndex == 2 {
                study_close(study);
            }
        }, study);
    } else {
        study_close(study);
    }
}

_on_open_external_analysis :: (using studyView : *StudyView) {
    Chamber.os_open_browser(Basic.tprint("%1%2", instance.config.analysis.externalSite, position_to_fen(study.currentGame.ply.position)));
}

_on_save :: (using studyView : *StudyView) {
    study_save(study);
}
