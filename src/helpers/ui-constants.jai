UiConstants :: struct #type_info_none {
    HeightLine :: 22.0; // @todo Should depend on font size.
    PaddingHorizontal :: 50.0;
    PaddingHorizontalSmall :: 4.0;
    PaddingHorizontalMedium :: 10.0;
    PaddingVertical :: 50.0;
    PaddingVerticalSmall :: 2.0;
    PaddingVerticalMedium :: 10.0;
    PaddingHorizontalSplit :: 20.0;
    PaddingHorizontalVariation :: 30.0;
    PaddingVerticalDecorumVariation :: 2.0;
    WidthDecorumVariation :: 4.0;
    PaddingCommentInline :: 5.0;
    HeightTabPageTitle :: 80.0;
    WidthSidebar :: 40.0;
    SizeTabAction :: 30.0;
    TranslucencyTabAction :: 0.85;
    HeightButtonDialog :: 30.0;
    WidthButtonDialog :: 100.0;
    WidthTextEntry :: WidthTextEntryWithoutPadding + 2 * PaddingHorizontalMedium;
    WidthTextEntryWithoutPadding :: 200.0;
    WidthLabel :: 2 * WidthTextEntry;

    DepthBackground :: 50.0;
    DepthMetaBoard :: -12.0;
    DepthMetaBoardInfo :: -1.0; // Relative to meta board.
    DepthMetaBoardViewArrow :: -0.05; // Multiplied by parent's scaling, can't use better unit.
    DepthMetaBoardViewMovingPiece :: -0.1; // Multipled
    DepthDialog :: -20.0;
    DepthDialogBackground :: 2.0; // Cumulative with DepthDialog.
    DepthDialogContentBackground :: 1.0; // Cumulative with DepthDialog.
    DepthDialogTextEntry :: -1.0; // Cumulative with DepthDialog.
    DepthDialogTextEntryLabel :: -1.0; // Cumulative with DepthDialogTextEntry.
    DepthDialogLabel :: -1.0; // Cumulative with DepthDialog.
    DepthDialogButton :: -1.0; // Cumulative with DepthDialog.
    DepthSidebar :: -1.0;
    DepthSidebarButton :: -10.0; // Needed to be selectable in front of things.
    DepthTab :: -10.0;
    DepthTabText :: -2.0;
    DepthTabMenu :: -2.0;
    DepthButtonTooltip :: -15.0;
}
