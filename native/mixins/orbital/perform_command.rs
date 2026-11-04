fn orbital_perform_command(game: &mut crate::game::Game<'_>, command: &str, ran: &mut bool) {
    crate::game::orbital_glue::perform_command(game, command, ran);
}
