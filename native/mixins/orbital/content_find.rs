fn orbital_content_find(dir: &Path, found: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut found = found;
    // Only the instance's horizon-mods/ (the game's content_root and its Mods page ask for it).
    if dir.file_name().is_none_or(|n| n != "horizon-mods") {
        return found;
    }
    let Some(instance) = dir.parent() else {
        return found;
    };
    let ours = instance.join("horizon-native-mods").join("orbital.hnmod");
    if !ours.is_file() || !crate::Package::has_manifest(&ours) {
        return found;
    }
    // A content mod `orbital` the player put in horizon-mods/ themselves is used instead.
    let id_of = |p: &PathBuf| crate::Package::read(p).ok().map(|p| p.manifest.id);
    if found.iter().any(|p| id_of(p).as_deref() == Some("orbital")) {
        return found;
    }
    found.push(ours);
    found
}
