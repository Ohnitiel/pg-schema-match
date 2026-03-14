#!/usr/bin/bash

process_files() {
    local curr_dir=".";

    if [ -n "$1" ]; then
	curr_dir="$1";
    fi;


    for file in "$curr_dir"/*; do
	if [ -f "$file" ]; then
	    if [[ ! " ${ignored_files[@]} " =~ " ${file} " ]]; then
		files_to_append+=("$file")
	    fi;
	fi;
	if [ -d "$file" ]; then
	    process_files "$curr_dir/$file";
	fi;
    done;
}

ignored_files=("./000_definitions_view.sql" "./000_pg_attribute_view.sql" "./generate_all.sh" "./all.sql" "./GEMINI.md" "./err.log")
files_to_append=()

process_files

cat "${files_to_append[@]}" > all.sql

cat all.sql | win32yank.exe -i
