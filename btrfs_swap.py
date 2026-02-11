    # 1. Identify swap subvolume
    swap_subvol = libcalamares.job.configuration.get("btrfsSwapSubvol", "/@swap")    
    # 2. Only fetch swap options if the subvolume actually exists in the list
    has_swap = any(s["subvolume"] == swap_subvol for s in btrfs_subvolumes)
    swap_options = get_mount_options("btrfs_swap", mount_options, partition) if has_swap else None

    # Step 3: Mount remaining subvolumes (like /home)
    for s in btrfs_subvolumes:
        if s["mountPoint"] == "/":
            libcalamares.globalstorage.insert("btrfsRootSubvolume", s["subvolume"])
            continue

        # Choose base options
        chosen_options = swap_options if (has_swap and s['subvolume'] == swap_subvol) else mount_options_string
        # Handle "breadcrumb" logic for empty subvolume names
        if s['subvolume']:
            # This tells Linux: "Put this specific subvolume here"
            sub_opts = f"subvol={s['subvolume']},{chosen_options}"
        else:
            # Mounting the entire filesystem (for swap?)
            sub_opts = chosen_options
        # This builds the path INSIDE your new root
        sub_path = root_mount_point + s["mountPoint"]
        os.makedirs(sub_path, exist_ok=True)

        if libcalamares.utils.mount(device, sub_path, fstype, sub_opts) == 0:
            mount_options_list.append({"mountpoint": s["mountPoint"], "option_string": mount_options_string})
        else:
            libcalamares.utils.warning(f"Failed to mount subvolume {s['subvolume']}")

