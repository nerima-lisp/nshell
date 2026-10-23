# M04: frecency directory jump

1. In a host shell, create isolated homes, XDG data directories, and test directories:

   ```sh
   scratch=$(mktemp -d)
   mkdir -p "$scratch/home" "$scratch/config" "$scratch/data" "$scratch/state"
   mkdir -p "$scratch/work-alpha" "$scratch/work-beta"
   export SCENARIO_SCRATCH="$scratch"
   nshell_bin=/path/to/candidate/bin/nshell
   ```

2. Set `nshell_bin` to the candidate executable. Launch it with `env HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/config" XDG_DATA_HOME="$scratch/data" XDG_STATE_HOME="$scratch/state" "$nshell_bin" --no-config`.
3. In nshell, visit `"$SCENARIO_SCRATCH/work-beta"` once. Return to `"$SCENARIO_SCRATCH"`, then visit `"$SCENARIO_SCRATCH/work-alpha"` ten times, returning to the scratch directory between visits so each visit is a separate navigation.
4. Invoke the documented frecency jump command and search using the shared fragment.
5. Accept the top-ranked `work-alpha` entry and inspect the resulting working directory. Exit nshell, record the result, then remove only the scratch directory created in step 1 with `rm -r "$scratch"`.

Pass when the jump opens `work-alpha` and the picker ranks it ahead of the less frequently visited `work-beta` entry. At the revision under test, if no public frecency jump command is documented, record the UC as unsupported and stop; do not infer one from private code.
