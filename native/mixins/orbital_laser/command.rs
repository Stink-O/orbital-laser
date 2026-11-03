fn orbital_command(game: &mut crate::game::Game<'_>, command: &str, ran: &mut bool) {
    if crate::game::orbital_glue::command(game, command) {
        *ran = true;
    }
}
