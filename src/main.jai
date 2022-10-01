// #import "Basic"()(MEMORY_DEBUGGER=true);

Sill :: #import "Sill";
Magma :: Sill.Magma;
Crater :: #import "Crater";
Chamber :: #import "Chamber";

Basic :: #import "Basic";
Debug :: #import "Debug";
Hash :: #import "Hash_Table";
Math :: #import "Math";
File :: #import "File";
Bucket_Array :: #import "Bucket_Array";
CommandLine :: #import "Command_Line";
for_expansion :: Hash.for_expansion;

#load "display/background.jai";
#load "display/button-bar.jai";
#load "display/board.jai";
#load "display/file-select.jai";
#load "display/list.jai";
#load "display/meta-board.jai";
#load "helpers/arrow-mesh.jai";
#load "helpers/entities.jai";
#load "helpers/fork-awesome.jai";
#load "helpers/rect-mesh.jai";
#load "helpers/text-mesh.jai";
#load "helpers/ui-constants.jai";
#load "structures/board-state.jai";
#load "structures/coord.jai";
#load "structures/game.jai";
#load "structures/piece.jai";
#load "structures/ply.jai";
#load "structures/position.jai";
#load "structures/variation.jai";
#load "readers/fen.jai";
#load "readers/pgn.jai";
#load "config.jai";
#load "controller.jai";
#load "message.jai";

// Feature ideas:
// @todo Change the selected ply visual to a rect around the ply. (But issues with ply.index == 0?)
// @todo Read comments to see if squares or moves are cited, and display arrows and such

instance : Instance;

Instance :: struct {
    engine : *Sill.Engine(SillMeta);

    shaders : struct {
        decorum : *Magma.Shader;
        monochrome : *Magma.Shader;
        text : *Magma.Shader;
        translucentMonochrome : *Magma.Shader;
    }

    game : Game;
    config : Config;
    persistence : Persistence;

    background : *BackgroundEntity;
    buttonBar : *ButtonBarEntity;
    controller : *ControllerEntity;
    list : *ListEntity;
    metaBoard : *MetaBoardEntity;
}

Arguments :: struct {
    pgn : string;
    config := "./assets/config.json";
}

persistence_commit :: () {
    // @fixme Do save the persistence file.
}

main :: () {
    Debug.init(); // For signal handlers
    Chamber.init_logger();
    context.log_level = .VERBOSE;

    // @todo Have a better command line parser, checking required arguments and such.
    success, args, setArgs := CommandLine.parse_arguments(Arguments);
    if !success then return;

    storagePath := Chamber.os_application_data_storage_path();
    read_json_as(*instance.config, args.config);
    read_json_as(*instance.persistence, Basic.tprint("%1%2", storagePath, ".sloubi-chess.json"), silentOnError = true);
    Basic.free(storagePath);

    instance.engine = Sill.create_engine(SillMeta, .{ eventHandler = _event_handler });

    _shaders_init();
    _fonts_init();

    instance.controller = controller_create();
    instance.background = background_create();
    instance.buttonBar = button_bar_create();
    instance.list = list_create();
    instance.metaBoard = meta_board_create();

    send(.SystemReflow);

    if setArgs.pgn {
        if load_pgn(args.pgn) {
            game_show(*instance.game);
        }
        // game_debug_dump(instance.game);
    } else {
        file_select_show(".pgn", (selectedFile : string) {
            if load_pgn(selectedFile) {
                game_show(*instance.game);
            }
        });
    }

    Sill.engine_run(instance.engine);

    // _cleanup();
    // Chamber.cleanup_logger();
    // Basic.report_memory_leaks();
}

#scope_file

_cleanup :: () {
    game_cleanup(*instance.game);
    config_cleanup(*instance.config);
    persistence_cleanup(*instance.persistence);

    Sill.destroy_engine(instance.engine);
}

_event_handler :: (event : Crater.Event) {
    if event.kind == Crater.Event.Kind.WindowSizeChanged {
        Magma.forward_renderer_extent(cast(*Magma.ForwardRenderer) instance.engine.renderer, instance.engine.options.windowExtent);
        send(.SystemReflow);
    } else if event.kind == Crater.Event.Kind.KeyPressed &&
              event.key.which == Crater.Key.F10 {
        instance.engine.options.logFps = !instance.engine.options.logFps;
    } else if event.kind == Crater.Event.Kind.KeyPressed &&
              event.key.which == Crater.Key.Escape {
        instance.engine.closingMainWindow = true;
    }
}

_fonts_init :: () {
    // @todo We're missing a notion in fonts, which would allow us to use a shared fallback.
    // Currently, we would need to duplicate the "dejaVu" fallback font for each family.
    boldFontFiles : [2]string;
    boldFontFiles[0] = Basic.tprint("./assets/fonts/%-Bold.ttf", instance.config.env.fontFamily);
    boldFontFiles[1] = "./assets/fonts/DejaVuSans.ttf";

    lightFontFiles : [3]string;
    lightFontFiles[0] = Basic.tprint("./assets/fonts/%-Light.ttf", instance.config.env.fontFamily);
    lightFontFiles[1] = "./assets/fonts/DejaVuSans.ttf";
    lightFontFiles[2] = "./assets/fonts/ForkAwesome.ttf";

    lightItalicFontFile := Basic.tprint("./assets/fonts/%-LightItalic.ttf", instance.config.env.fontFamily);
    monoFontFile := Basic.tprint("./assets/fonts/%-Regular.ttf", instance.config.env.monoFontFamily);

    Sill.fonts_register(instance.engine, "mainLight", lightFontFiles, cast(float) instance.config.env.fontSize);
    Sill.fonts_register(instance.engine, "mainLightItalic", lightItalicFontFile, cast(float) instance.config.env.fontSize);
    Sill.fonts_register(instance.engine, "mainBold", boldFontFiles, cast(float) instance.config.env.fontSize);
    Sill.fonts_register(instance.engine, "mono", monoFontFile, cast(float) instance.config.env.fontSize);

    // Preload for most common glyphs
    Sill.fonts_glyph_infos(instance.engine, "mainLight", "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?-+*/=()[]{}:;<>|&@#$%^~`'\"\\");
    Sill.fonts_glyph_infos(instance.engine, "mainBold", "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.,!?-+*/=()[]{}:;<>|&@#$%^~`'\"\\");
}

_shaders_init :: () {
    instance.shaders.monochrome = Magma.create_shader(instance.engine.renderer, "./assets/materials/monochrome");
    instance.shaders.text = Magma.create_shader(instance.engine.renderer, "./assets/materials/text", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
    instance.shaders.translucentMonochrome = Magma.create_shader(instance.engine.renderer, "./assets/materials/translucent-monochrome", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
    instance.shaders.decorum = Magma.create_shader(instance.engine.renderer, "./assets/materials/decorum", .{ alphaBlendingEnabled = true });
}

#import "Math";
