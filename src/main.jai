// #import "Basic"()(MEMORY_DEBUGGER=true);

Sill :: #import "Sill";
Magma :: Sill.Magma;
Crater :: #import "Crater";
Chamber :: #import "Chamber";

Basic :: #import "Basic";
Hash :: #import "Hash_Table";
Math :: #import "Math";
File :: #import "File";

#load "display/background.jai";
#load "display/board.jai";
#load "display/file-select.jai";
#load "display/list.jai";
#load "helpers/text-mesh.jai";
#load "structures/coord.jai";
#load "structures/game.jai";
#load "structures/piece.jai";
#load "structures/position.jai";
#load "readers/fen.jai";
#load "readers/pgn.jai";
#load "config.jai";
#load "controller.jai";

CommandLine :: #import "Command_Line";

instance : Instance;

Instance :: struct {
    engine : *Sill.Engine(SillMeta);

    fonts : struct {
        light : Chamber.Font;
        lightItalic : Chamber.Font;
        bold : Chamber.Font;
    };

    background : Background;
    board : *BoardEntity;
    config : Config;
    controller : *ControllerEntity;
    fileSelect : *FileSelectEntity;
    game : Game;
    list : List;
    persistence : Persistence;
}

Arguments :: struct {
    pgn : string;
    config := "./assets/config.json";
}

main :: () {
    Chamber.init_logger();
    context.log_level = .VERBOSE;

    // @todo Have a better command line parser, checking required arguments and such.
    success, args, setArgs := CommandLine.parse_arguments(Arguments);
    if !success then return;

    readJsonAs(*instance.config, args.config);
    readJsonAs(*instance.persistence, "/home/alexis/.sloubi-chess.json"); // @fixme Hardcoded path...

    // @todo We're missing a notion in fonts, which would allow us to use a shared fallback.
    // Currently, we would need to duplicate the "dejaVu" fallback font for each family.
    boldFontFiles : [2]string;
    boldFontFiles[0] = Basic.tprint("./assets/fonts/%-Bold.ttf", instance.config.moves.fontFamily);
    boldFontFiles[1] = "./assets/fonts/DejaVuSans.ttf";

    lightFontFiles : [3]string;
    lightFontFiles[0] = Basic.tprint("./assets/fonts/%-Light.ttf", instance.config.moves.fontFamily);
    lightFontFiles[1] = "./assets/fonts/DejaVuSans.ttf";
    lightFontFiles[2] = "./assets/fonts/ForkAwesome.ttf";

    instance.engine = Sill.create_engine(SillMeta);
    instance.fonts.light = Chamber.font_load(lightFontFiles, cast(float) instance.config.moves.fontSize);
    instance.fonts.lightItalic = Chamber.font_load(Basic.tprint("./assets/fonts/%-LightItalic.ttf", instance.config.moves.fontFamily), cast(float) instance.config.moves.fontSize);
    instance.fonts.bold = Chamber.font_load(boldFontFiles, cast(float) instance.config.moves.fontSize);

    controller_init();
    board_init();
    background_init();
    list_init();

    if setArgs.pgn {
        load_pgn(args.pgn);
        // game_debug_dump(instance.game);
    } else {
        file_select_show();
    }

    Sill.engine_run(instance.engine);

    // cleanup();
    // Chamber.cleanup_logger();
    // Basic.report_memory_leaks();
}

#scope_file

cleanup :: () {
    Sill.destroy_engine(instance.engine);
}

#import "Math";
