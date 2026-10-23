# T04: Compare documentation with the executable

## Procedure

1. Select the immediately preceding published release and record its tag or revision. Build the candidate executable and create a temporary home and working directory. If no earlier release is published, record this UC as not run.
2. Compare the candidate documentation with that release and list only the behavior and setup claims changed in the getting-started guide, customization guide, built-in reference, man page, and help output. Record each changed claim's document location.
3. For each listed claim, run the documented command with the candidate executable and compare its output, exit status, and side effects with the text.
4. Check setup paths and option names against the executable's help. Record each mismatch with the document location and observed output.

## Pass condition

Every changed claim matches the candidate behavior, and each documented example works from its stated starting conditions. Record the comparison revision, executable build, and platform so another reviewer can repeat the comparison.
