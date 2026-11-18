fn orbital_content_find(dir: &Path, found: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut found = found;
    // Only the instance's horizon-mods/ (the game's content_root and its Mods page ask for it).
    if dir.file_name().is_none_or(|n| n != "horizon-mods") {
        return found;
    }
    let Some(instance) = dir.parent() else {
        return found;
    };
    // The native file by its mod id: the launcher installs it as `orbital.hnmod`, and one put there by hand may keep
    // its download's name (`orbital-laser-native-vX.Y.Z.hnmod`).
    let natives = instance.join("horizon-native-mods");
    let is_ours = |p: &PathBuf| {
        p.is_file()
            && crate::Package::has_manifest(p)
            && crate::Package::read(p).ok().is_some_and(|k| k.manifest.id == "orbital")
    };
    let named = natives.join("orbital.hnmod");
    let ours = if is_ours(&named) {
        named
    } else {
        let mut files: Vec<PathBuf> = std::fs::read_dir(&natives)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "hnmod"))
            .collect();
        files.sort();
        match files.into_iter().find(|p| is_ours(p)) {
            Some(p) => p,
            None => return found,
        }
    };
    // A content mod `orbital` the player put in horizon-mods/ themselves is used instead.
    let id_of = |p: &PathBuf| crate::Package::read(p).ok().map(|p| p.manifest.id);
    if found.iter().any(|p| id_of(p).as_deref() == Some("orbital")) {
        return found;
    }
    found.push(ours);
    found
}
