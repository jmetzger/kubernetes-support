# Installation und verwenden für Projet 

## Voraussetzungen

  * Cluster muss eingerichtet sein in .kube/config und muss erreichbar sein 

## Schritt 1: Installation (lokal für jeden Nutzer) 

  * Ihr könnte es aber auch zentral nach /usr/local/bin installieren 

```
# Ihr seid im tln benutzer
cd

# Das ist ein gepatchte Version, aktuell gibt es noch keine "original" gefixte Version
# https://github.com/blaumann-intern/argocd-autopilot/releases/tag/v0.4.20

curl -L --output - https://github.com/blaumann-intern/argocd-autopilot/releases/download/v0.4.20/argocd-autopilot-linux-amd64.tar.gz | tar zx
mv argocd-autopilot-* argocd-autopilot

# Versionsnummer wird bei dieser gepatchten version leider nicht angezeigt :o(
./argocd-autopilot version
./argocd-autopilot help 
```

## Schritt 2: Autcomplete verwenden 

```
cd
./argocd-autopilot <TAB><TAB>
```

## Schritt 3: gitops-repo anlegen 

```
# in gitlab einloggen mit teilnehmer-nr
# z.B. training.tn1
# Bitte keine README.md rein, muss leer sein
```

## Schritt 4: Personal Access Token (PAT) in gitlab anlegen 

https://gitlab.com/-/user_settings/personal_access_tokens?state=active&sort=expires_asc

<img width="1337" height="522" alt="image" src="https://github.com/user-attachments/assets/e2cf8141-45d5-4011-928e-e679cfb9186d" />

## Schritt 5: env-Variablen setzten und bootstrap durchführen

```
export GIT_TOKEN=<hier-dein-token>
# z.B. gitlab.com/training.tn1/gitops-argocd-jochen.git
export GIT_REPO=<hier-deine-repo-url>
```

```
# Das bevölkert das Repo mit den richtigen Einstellungen um zu starten 
cd
./argocd-autopilot repo bootstrap
```

```
kubectl -n argocd get pods
kubectl -n argocd get applications 
```

```
# Du kannst dir das dann direkt im Repo anschauen
```

## Schritt 6: ServerSideApply aktivieren

ArgoCD verwaltet sich nach dem Bootstrap selbst über die Application `argo-cd`. Ohne
Server-Side Apply (SSA) syncet ArgoCD per Client-Side Apply (CSA) — das fuehrt bei
spaeteren Kustomize-Patches (z.B. der WebInterface-LoadBalancer-Uebung) zu
Synchronisierungsproblemen, weil ArgoCD dann mit anderen Feld-Ownern (z.B. dem
DigitalOcean Cloud-Controller-Manager) um dieselben Felder "kaempft".

### Wichtig: nur Resource-Level-Annotationen sind zuverlaessig

Ein globaler SSA-Default ueber `application.sync.options: ServerSideApply=true` in der
`argocd-cm`-ConfigMap **wirkt nicht zuverlaessig** — weder fuer gewoehnliche Ressourcen
(z.B. den `argocd-server`-Service) noch fuer CRDs. Das laesst sich leicht falsch
verifizieren: `managedFields` kann einen alten `argocd-controller | Apply`-Eintrag von
einem frueheren Sync zeigen, obwohl der **aktuelle** Sync trotzdem wieder CSA nutzt. Die
einzige zuverlaessige Pruefung ist, ob die Annotation
`kubectl.kubernetes.io/last-applied-configuration` existiert — SSA schreibt sie nie, CSA
immer:

```bash
kubectl get svc argocd-server -n argocd -o yaml | grep -c last-applied-configuration
# 0 = SSA aktiv. 1 = trotz Default immer noch CSA.
```

Deshalb setzen wir SSA direkt als **Annotation auf jeder Ressource**, die es braucht — nicht
nur global.

```
cd ~/gitops/bootstrap/argo-cd
```

In `kustomization.yaml` Patches fuer `argocd-server` (Service), `argocd-cm` (globaler
Fallback-Default fuer alles andere) und die `applicationsets`-CRD ergaenzen:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
- github.com/argoproj-labs/argocd-autopilot/manifests/base?ref=v0.4.20
patches:
- patch: |-
    apiVersion: v1
    kind: Service
    metadata:
      name: argocd-server
      annotations:
        argocd.argoproj.io/sync-options: ServerSideApply=true
    spec:
      type: LoadBalancer
  target:
    kind: Service
    name: argocd-server
- patch: |-
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-cm
    data:
      application.sync.options: ServerSideApply=true
  target:
    kind: ConfigMap
    name: argocd-cm
- patch: |-
    apiVersion: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    metadata:
      name: applicationsets.argoproj.io
      annotations:
        argocd.argoproj.io/sync-options: ServerSideApply=true,ClientSideApplyMigration=false
  target:
    kind: CustomResourceDefinition
    name: applicationsets.argoproj.io
```

> **Hinweis:** Der `argocd-server`-Patch enthaelt hier schon den `type: LoadBalancer`-Teil
> aus der WebInterface-Uebung mit dazu — wenn ihr Schritt 6 vor dieser Uebung macht, lasst
> den `spec:`-Block einfach weg und ergaenzt ihn erst dort.

```
cd ~/gitops
git add bootstrap/argo-cd/kustomization.yaml
git commit -m "enable ServerSideApply via resource-level annotations"
git push
```

Sync anstossen:

```
kubectl -n argocd patch application argo-cd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
kubectl -n argocd patch application argo-cd --type merge -p '{"operation":{"sync":{}}}'
```

### Warum die CRD-Annotation zusaetzlich noetig ist

Die `applicationsets.argoproj.io`-CRD ist zu gross fuer das 262144-Byte-Annotation-Limit.
ArgoCDs eigener CSA→SSA-Migrationsmechanismus versucht beim Umstieg trotzdem, den alten
`kubectl-client-side-apply`-Feld-Manager abzuloesen — und scheitert dabei selbst an genau
diesem Limit (`metadata.annotations: Too long: may not be more than 262144 bytes`), bei
**jedem** Sync erneut. Das laesst die Application im GUI dauerhaft auf "Syncing" haengen.
`ClientSideApplyMigration=false` deaktiviert diesen Migrationsschritt. Details:
[argoproj/argo-cd#26279](https://github.com/argoproj/argo-cd/issues/26279).

Falls die Application schon in diesem haengenden Zustand ist (`status.operationState.phase:
Running` mit obiger Fehlermeldung, wiederholt), erst den haengenden Sync abbrechen, bevor
man den Fix pusht:

```
kubectl -n argocd patch application argo-cd --type merge -p '{"operation":null}'
```

**Verifizieren (Service):**

```
kubectl get svc argocd-server -n argocd -o yaml | grep -c last-applied-configuration
```

Erwartete Ausgabe: `0`. External-IP und Alter (`AGE`) der Ressource bleiben dabei
unveraendert — der Service wird nur neu appliziert, nicht neu angelegt.

**Verifizieren (Applications):**

```
kubectl get applications -n argocd
```

Erwartete Ausgabe: alle 4 Applications (`argo-cd`, `autopilot-bootstrap`,
`cluster-resources-in-cluster`, `root`) `Synced`/`Healthy`.

## Optional : Autocompletion (bereits installiert) 

```
# autocompletion lässt sich nur mit dem originalen Binary erstellen
# Der Patch hat hier noch probleme.

# Ich habe jetzt completion bereits in /etc/bash_completion.d/argocd-autopilot eingerichtet
sudo su -
nano /etc/bash
```

```
# bash completion V2 for argocd-autopilot                     -*- shell-script -*-

__argocd-autopilot_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE-} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Macs have bash3 for which the bash-completion package doesn't include
# _init_completion. This is a minimal version of that function.
__argocd-autopilot_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

# This function calls the argocd-autopilot program to obtain the completion
# results and the directive.  It fills the 'out' and 'directive' vars.
__argocd-autopilot_get_completion_results() {
    local requestComp lastParam lastChar args

    # Prepare the command to request completions for the program.
    # Calling ${words[0]} instead of directly argocd-autopilot allows handling aliases
    args=("${words[@]:1}")
    requestComp="${words[0]} __complete ${args[*]}"

    lastParam=${words[$((${#words[@]}-1))]}
    lastChar=${lastParam:$((${#lastParam}-1)):1}
    __argocd-autopilot_debug "lastParam ${lastParam}, lastChar ${lastChar}"

    if [[ -z ${cur} && ${lastChar} != = ]]; then
        # If the last parameter is complete (there is a space following it)
        # We add an extra empty parameter so we can indicate this to the go method.
        __argocd-autopilot_debug "Adding extra empty parameter"
        requestComp="${requestComp} ''"
    fi

    # When completing a flag with an = (e.g., argocd-autopilot -n=<TAB>)
    # bash focuses on the part after the =, so we need to remove
    # the flag part from $cur
    if [[ ${cur} == -*=* ]]; then
        cur="${cur#*=}"
    fi

    __argocd-autopilot_debug "Calling ${requestComp}"
    # Use eval to handle any environment variables and such
    out=$(eval "${requestComp}" 2>/dev/null)

    # Extract the directive integer at the very end of the output following a colon (:)
    directive=${out##*:}
    # Remove the directive
    out=${out%:*}
    if [[ ${directive} == "${out}" ]]; then
        # There is not directive specified
        directive=0
    fi
    __argocd-autopilot_debug "The completion directive is: ${directive}"
    __argocd-autopilot_debug "The completions are: ${out}"
}

__argocd-autopilot_process_completion_results() {
    local shellCompDirectiveError=1
    local shellCompDirectiveNoSpace=2
    local shellCompDirectiveNoFileComp=4
    local shellCompDirectiveFilterFileExt=8
    local shellCompDirectiveFilterDirs=16
    local shellCompDirectiveKeepOrder=32

    if (((directive & shellCompDirectiveError) != 0)); then
        # Error code.  No completion.
        __argocd-autopilot_debug "Received error from custom completion go code"
        return
    else
        if (((directive & shellCompDirectiveNoSpace) != 0)); then
            if [[ $(type -t compopt) == builtin ]]; then
                __argocd-autopilot_debug "Activating no space"
                compopt -o nospace
            else
                __argocd-autopilot_debug "No space directive not supported in this version of bash"
            fi
        fi
        if (((directive & shellCompDirectiveKeepOrder) != 0)); then
            if [[ $(type -t compopt) == builtin ]]; then
                # no sort isn't supported for bash less than < 4.4
                if [[ ${BASH_VERSINFO[0]} -lt 4 || ( ${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -lt 4 ) ]]; then
                    __argocd-autopilot_debug "No sort directive not supported in this version of bash"
                else
                    __argocd-autopilot_debug "Activating keep order"
                    compopt -o nosort
                fi
            else
                __argocd-autopilot_debug "No sort directive not supported in this version of bash"
            fi
        fi
        if (((directive & shellCompDirectiveNoFileComp) != 0)); then
            if [[ $(type -t compopt) == builtin ]]; then
                __argocd-autopilot_debug "Activating no file completion"
                compopt +o default
            else
                __argocd-autopilot_debug "No file completion directive not supported in this version of bash"
            fi
        fi
    fi

    # Separate activeHelp from normal completions
    local completions=()
    local activeHelp=()
    __argocd-autopilot_extract_activeHelp

    if (((directive & shellCompDirectiveFilterFileExt) != 0)); then
        # File extension filtering
        local fullFilter="" filter filteringCmd

        # Do not use quotes around the $completions variable or else newline
        # characters will be kept.
        for filter in ${completions[*]}; do
            fullFilter+="$filter|"
        done

        filteringCmd="_filedir $fullFilter"
        __argocd-autopilot_debug "File filtering command: $filteringCmd"
        $filteringCmd
    elif (((directive & shellCompDirectiveFilterDirs) != 0)); then
        # File completion for directories only

        local subdir
        subdir=${completions[0]}
        if [[ -n $subdir ]]; then
            __argocd-autopilot_debug "Listing directories in $subdir"
            pushd "$subdir" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1 || return
        else
            __argocd-autopilot_debug "Listing directories in ."
            _filedir -d
        fi
    else
        __argocd-autopilot_handle_completion_types
    fi

    __argocd-autopilot_handle_special_char "$cur" :
    __argocd-autopilot_handle_special_char "$cur" =

    # Print the activeHelp statements before we finish
    __argocd-autopilot_handle_activeHelp
}

__argocd-autopilot_handle_activeHelp() {
    # Print the activeHelp statements
    if ((${#activeHelp[*]} != 0)); then
        if [ -z $COMP_TYPE ]; then
            # Bash v3 does not set the COMP_TYPE variable.
            printf "\n";
            printf "%s\n" "${activeHelp[@]}"
            printf "\n"
            __argocd-autopilot_reprint_commandLine
            return
        fi

        # Only print ActiveHelp on the second TAB press
        if [ $COMP_TYPE -eq 63 ]; then
            printf "\n"
            printf "%s\n" "${activeHelp[@]}"

            if ((${#COMPREPLY[*]} == 0)); then
                # When there are no completion choices from the program, file completion
                # may kick in if the program has not disabled it; in such a case, we want
                # to know if any files will match what the user typed, so that we know if
                # there will be completions presented, so that we know how to handle ActiveHelp.
                # To find out, we actually trigger the file completion ourselves;
                # the call to _filedir will fill COMPREPLY if files match.
                if (((directive & shellCompDirectiveNoFileComp) == 0)); then
                    __argocd-autopilot_debug "Listing files"
                    _filedir
                fi
            fi

            if ((${#COMPREPLY[*]} != 0)); then
                # If there are completion choices to be shown, print a delimiter.
                # Re-printing the command-line will automatically be done
                # by the shell when it prints the completion choices.
                printf -- "--"
            else
                # When there are no completion choices at all, we need
                # to re-print the command-line since the shell will
                # not be doing it itself.
                __argocd-autopilot_reprint_commandLine
            fi
        elif [ $COMP_TYPE -eq 37 ] || [ $COMP_TYPE -eq 42 ]; then
            # For completion type: menu-complete/menu-complete-backward and insert-completions
            # the completions are immediately inserted into the command-line, so we first
            # print the activeHelp message and reprint the command-line since the shell won't.
            printf "\n"
            printf "%s\n" "${activeHelp[@]}"

            __argocd-autopilot_reprint_commandLine
        fi
    fi
}

__argocd-autopilot_reprint_commandLine() {
    # The prompt format is only available from bash 4.4.
    # We test if it is available before using it.
    if (x=${PS1@P}) 2> /dev/null; then
        printf "%s" "${PS1@P}${COMP_LINE[@]}"
    else
        # Can't print the prompt.  Just print the
        # text the user had typed, it is workable enough.
        printf "%s" "${COMP_LINE[@]}"
    fi
}

# Separate activeHelp lines from real completions.
# Fills the $activeHelp and $completions arrays.
__argocd-autopilot_extract_activeHelp() {
    local activeHelpMarker="_activeHelp_ "
    local endIndex=${#activeHelpMarker}

    while IFS='' read -r comp; do
        [[ -z $comp ]] && continue

        if [[ ${comp:0:endIndex} == $activeHelpMarker ]]; then
            comp=${comp:endIndex}
            __argocd-autopilot_debug "ActiveHelp found: $comp"
            if [[ -n $comp ]]; then
                activeHelp+=("$comp")
            fi
        else
            # Not an activeHelp line but a normal completion
            completions+=("$comp")
        fi
    done <<<"${out}"
}

__argocd-autopilot_handle_completion_types() {
    __argocd-autopilot_debug "__argocd-autopilot_handle_completion_types: COMP_TYPE is $COMP_TYPE"

    case $COMP_TYPE in
    37|42)
        # Type: menu-complete/menu-complete-backward and insert-completions
        # If the user requested inserting one completion at a time, or all
        # completions at once on the command-line we must remove the descriptions.
        # https://github.com/spf13/cobra/issues/1508

        # If there are no completions, we don't need to do anything
        (( ${#completions[@]} == 0 )) && return 0

        local tab=$'\t'

        # Strip any description and escape the completion to handled special characters
        IFS=$'\n' read -ra completions -d '' < <(printf "%q\n" "${completions[@]%%$tab*}")

        # Only consider the completions that match
        IFS=$'\n' read -ra COMPREPLY -d '' < <(IFS=$'\n'; compgen -W "${completions[*]}" -- "${cur}")

        # compgen looses the escaping so we need to escape all completions again since they will
        # all be inserted on the command-line.
        IFS=$'\n' read -ra COMPREPLY -d '' < <(printf "%q\n" "${COMPREPLY[@]}")
        ;;

    *)
        # Type: complete (normal completion)
        __argocd-autopilot_handle_standard_completion_case
        ;;
    esac
}

__argocd-autopilot_handle_standard_completion_case() {
    local tab=$'\t'

    # If there are no completions, we don't need to do anything
    (( ${#completions[@]} == 0 )) && return 0

    # Short circuit to optimize if we don't have descriptions
    if [[ "${completions[*]}" != *$tab* ]]; then
        # First, escape the completions to handle special characters
        IFS=$'\n' read -ra completions -d '' < <(printf "%q\n" "${completions[@]}")
        # Only consider the completions that match what the user typed
        IFS=$'\n' read -ra COMPREPLY -d '' < <(IFS=$'\n'; compgen -W "${completions[*]}" -- "${cur}")

        # compgen looses the escaping so, if there is only a single completion, we need to
        # escape it again because it will be inserted on the command-line.  If there are multiple
        # completions, we don't want to escape them because they will be printed in a list
        # and we don't want to show escape characters in that list.
        if (( ${#COMPREPLY[@]} == 1 )); then
            COMPREPLY[0]=$(printf "%q" "${COMPREPLY[0]}")
        fi
        return 0
    fi

    local longest=0
    local compline
    # Look for the longest completion so that we can format things nicely
    while IFS='' read -r compline; do
        [[ -z $compline ]] && continue

        # Before checking if the completion matches what the user typed,
        # we need to strip any description and escape the completion to handle special
        # characters because those escape characters are part of what the user typed.
        # Don't call "printf" in a sub-shell because it will be much slower
        # since we are in a loop.
        printf -v comp "%q" "${compline%%$tab*}" &>/dev/null || comp=$(printf "%q" "${compline%%$tab*}")

        # Only consider the completions that match
        [[ $comp == "$cur"* ]] || continue

        # The completions matches.  Add it to the list of full completions including
        # its description.  We don't escape the completion because it may get printed
        # in a list if there are more than one and we don't want show escape characters
        # in that list.
        COMPREPLY+=("$compline")

        # Strip any description before checking the length, and again, don't escape
        # the completion because this length is only used when printing the completions
        # in a list and we don't want show escape characters in that list.
        comp=${compline%%$tab*}
        if ((${#comp}>longest)); then
            longest=${#comp}
        fi
    done < <(printf "%s\n" "${completions[@]}")

    # If there is a single completion left, remove the description text and escape any special characters
    if ((${#COMPREPLY[*]} == 1)); then
        __argocd-autopilot_debug "COMPREPLY[0]: ${COMPREPLY[0]}"
        COMPREPLY[0]=$(printf "%q" "${COMPREPLY[0]%%$tab*}")
        __argocd-autopilot_debug "Removed description from single completion, which is now: ${COMPREPLY[0]}"
    else
        # Format the descriptions
        __argocd-autopilot_format_comp_descriptions $longest
    fi
}

__argocd-autopilot_handle_special_char()
{
    local comp="$1"
    local char=$2
    if [[ "$comp" == *${char}* && "$COMP_WORDBREAKS" == *${char}* ]]; then
        local word=${comp%"${comp##*${char}}"}
        local idx=${#COMPREPLY[*]}
        while ((--idx >= 0)); do
            COMPREPLY[idx]=${COMPREPLY[idx]#"$word"}
        done
    fi
}

__argocd-autopilot_format_comp_descriptions()
{
    local tab=$'\t'
    local comp desc maxdesclength
    local longest=$1

    local i ci
    for ci in ${!COMPREPLY[*]}; do
        comp=${COMPREPLY[ci]}
        # Properly format the description string which follows a tab character if there is one
        if [[ "$comp" == *$tab* ]]; then
            __argocd-autopilot_debug "Original comp: $comp"
            desc=${comp#*$tab}
            comp=${comp%%$tab*}

            # $COLUMNS stores the current shell width.
            # Remove an extra 4 because we add 2 spaces and 2 parentheses.
            maxdesclength=$(( COLUMNS - longest - 4 ))

            # Make sure we can fit a description of at least 8 characters
            # if we are to align the descriptions.
            if ((maxdesclength > 8)); then
                # Add the proper number of spaces to align the descriptions
                for ((i = ${#comp} ; i < longest ; i++)); do
                    comp+=" "
                done
            else
                # Don't pad the descriptions so we can fit more text after the completion
                maxdesclength=$(( COLUMNS - ${#comp} - 4 ))
            fi

            # If there is enough space for any description text,
            # truncate the descriptions that are too long for the shell width
            if ((maxdesclength > 0)); then
                if ((${#desc} > maxdesclength)); then
                    desc=${desc:0:$(( maxdesclength - 1 ))}
                    desc+="…"
                fi
                comp+="  ($desc)"
            fi
            COMPREPLY[ci]=$comp
            __argocd-autopilot_debug "Final comp: $comp"
        fi
    done
}

__start_argocd-autopilot()
{
    local cur prev words cword split

    COMPREPLY=()

    # Call _init_completion from the bash-completion package
    # to prepare the arguments properly
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -n =: || return
    else
        __argocd-autopilot_init_completion -n =: || return
    fi

    __argocd-autopilot_debug
    __argocd-autopilot_debug "========= starting completion logic =========="
    __argocd-autopilot_debug "cur is ${cur}, words[*] is ${words[*]}, #words[@] is ${#words[@]}, cword is $cword"

    # The user could have moved the cursor backwards on the command-line.
    # We need to trigger completion from the $cword location, so we need
    # to truncate the command-line ($words) up to the $cword location.
    words=("${words[@]:0:$cword+1}")
    __argocd-autopilot_debug "Truncated words[*]: ${words[*]},"

    local out directive
    __argocd-autopilot_get_completion_results
    __argocd-autopilot_process_completion_results
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_argocd-autopilot argocd-autopilot
else
    complete -o default -o nospace -F __start_argocd-autopilot argocd-autopilot
fi

# ex: ts=4 sw=4 et filetype=sh
```

```
# Greift jetzt bei jedem einloggen oder:
sudo su -
```
