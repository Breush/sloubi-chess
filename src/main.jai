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
#load "helpers/fork-awesome.jai";
#load "helpers/arrow-mesh.jai";
#load "helpers/rect-mesh.jai";
#load "helpers/text-mesh.jai";
#load "helpers/ui-constants.jai";
#load "structures/coord.jai";
#load "structures/game.jai";
#load "structures/piece.jai";
#load "structures/position.jai";
#load "readers/fen.jai";
#load "readers/pgn.jai";
#load "config.jai";
#load "controller.jai";

instance : Instance;

Instance :: struct {
    engine : *Sill.Engine(SillMeta);

    fonts : struct {
        light : Chamber.Font;
        lightItalic : Chamber.Font;
        bold : Chamber.Font;
    };

    shaders : struct {
        monochrome : *Magma.Shader;
        text : *Magma.Shader;
        translucentMonochrome : *Magma.Shader;
    }

    background : Background;
    metaBoard : *MetaBoardEntity;
    buttonBar : ButtonBar;
    config : Config;
    controller : *ControllerEntity;
    fileSelect : *FileSelectEntity;
    game : Game;
    list : *ListEntity;
    persistence : Persistence;
}

Arguments :: struct {
    pgn : string;
    config := "./assets/config.json";
}

main :: () {
    Debug.init(); // For signal handlers
    Chamber.init_logger();
    context.log_level = .VERBOSE;

    // @todo Have a better command line parser, checking required arguments and such.
    success, args, setArgs := CommandLine.parse_arguments(Arguments);
    if !success then return;

    storagePath := Chamber.os_application_data_storage_path();
    readJsonAs(*instance.config, args.config);
    readJsonAs(*instance.persistence, Basic.tprint("%1%2", storagePath, ".sloubi-chess.json"), silentOnError = true);
    Basic.free(storagePath);

    instance.engine = Sill.create_engine(SillMeta, .{ eventHandler = _event_handler });

    _shaders_init();
    _fonts_init();
    controller_init();
    meta_board_init();
    background_init();
    list_init();
    button_bar_init();

    if setArgs.pgn {
        load_pgn(args.pgn);
        // game_debug_dump(instance.game);
    } else {
        file_select_show(".pgn", (selectedFile : string) {
            load_pgn(selectedFile);
        });
    }

    Sill.engine_run(instance.engine);

    // _cleanup();
    // Chamber.cleanup_logger();
    // Basic.report_memory_leaks();
}

reflow :: () {
    background_reflow();
    button_bar_reflow();
    file_select_reflow();
    list_reflow();
    meta_board_reflow();
}

#scope_file

_cleanup :: () {
    Sill.destroy_engine(instance.engine);

    Basic.free(instance.config.board.pieces);
    Basic.free(instance.config.env.fontFamily);
    Basic.free(instance.persistence.fileSelect.lastPath);

    game_cleanup(*instance.game);
    _fonts_cleanup();
}

_event_handler :: (event : Crater.Event) {
    if event.kind == Crater.Event.Kind.WindowSizeChanged {
        Magma.forward_renderer_extent(cast(*Magma.ForwardRenderer) instance.engine.renderer, instance.engine.options.windowExtent);
        setup_orthographic_camera();
        reflow();
    }
    else if event.kind == Crater.Event.Kind.KeyPressed &&
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

    instance.fonts.light = Chamber.font_load(lightFontFiles, cast(float) instance.config.env.fontSize);
    instance.fonts.lightItalic = Chamber.font_load(Basic.tprint("./assets/fonts/%-LightItalic.ttf", instance.config.env.fontFamily), cast(float) instance.config.env.fontSize);
    instance.fonts.bold = Chamber.font_load(boldFontFiles, cast(float) instance.config.env.fontSize);
}

_fonts_cleanup :: () {
    Chamber.font_free(*instance.fonts.light);
    Chamber.font_free(*instance.fonts.lightItalic);
    Chamber.font_free(*instance.fonts.bold);
}

_shaders_init :: () {
    instance.shaders.monochrome = Magma.create_shader(instance.engine.renderer, "./assets/materials/monochrome");
    instance.shaders.text = Magma.create_shader(instance.engine.renderer, "./assets/materials/text", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
    instance.shaders.translucentMonochrome = Magma.create_shader(instance.engine.renderer, "./assets/materials/translucent-monochrome", .{ depthWriteEnabled = false, alphaBlendingEnabled = true });
}

#import "Math";
