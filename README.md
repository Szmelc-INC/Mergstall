# Mergstall v2
![image](https://github.com/user-attachments/assets/7c6c92e8-c795-4b03-8501-da502dcb19c5)

## [Important changes in v2]
> Mergstall v2 had some big changes to
> `Defining paths`\
> ALL paths are excluded by default, unless specified in whitelist.conf \
> Prefix each line with `+` to include, and `-` to exclude\
> `- /path/` - does nothing.\
> `- /path/*` - will exclude ONLY files that are in `/path/`, but NOT folders and files within them.\
> `- /path/**` - will exclude entire `/path/` directory and its contents\
> Excluding entire path with `/path/**`, will prevent you from including it's subpath `/path/path2/**`.\
> If same one path will is defined both in whitelist.conf & blacklist.conf, it will be excluded. \
> If `/path/path2/**` is whitelisted, then everything within `/path2/**` will be included, but nothing from `/path/` except `/path2/` itself. 



## Setup on non Entropy systems
> Install dependencies, `rsync zip grub2` and also `figlet lolcat boxes` for visual enchancement \
> Create `/bin/mergstall.d/` directory \
> Put `mergstall.sh`, `whitelist.conf` and `blacklist.conf` into `/bin/mergstall.d/` \
> Run mergstall directly or create a symlink in `/bin/` for easy access.

## Demo
<a href="https://www.youtube.com/watch?v=saWgK_pwCyw">
    <img src="https://i.imgur.com/i28JMRS.png" alt="Mergstall" width="600">
</a>

[Szmelc Incorporated YouTube Channel](https://www.youtube.com/@Szmelc-INC)
