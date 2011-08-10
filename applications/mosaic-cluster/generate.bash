#!/bin/bash

set -e -E -u -o pipefail || exit 1
test "${#}" -eq 0

cd -- "$( dirname -- "$( readlink -e -- "${0}" )" )"

rm -Rf ./.generated
mkdir ./.generated

(
	cat <<'EOS'
-module (mosaic_static_resources).
-export ([contents/1]).
EOS
	find ./resources -type f -print \
	| while read _file ; do
		case "${_file}" in
			( *.css ) _mime='text/css' ;;
			( *.js ) _mime='application/javascript' ;;
			( *.html ) _mime='text/html' ;;
			( * ) _mime='application/octet-stream' ;;
		esac
		echo "contents (<<\"${_file#./resources}\">>) ->"
		echo "	{ok, <<\"${_mime}\">>, <<"
		cat "${_file}" \
		| od -v -A x -t x1 -w16 \
		| sed -r \
				-e 's!^[0-9a-f]{6}(( [0-9a-f]{2}){0,128})$!\1!g' \
				-e 'tok1' -e 'Q1' -e ':ok1' \
				-e 's! !!g' -e '/^$/d' \
				-e 's!([0-9a-f]{2})!16#\1, !g' -e 's!^(.*), $!\t\t<<\1>> / binary,!g'
		echo '		<<>> / binary>>};'
	done
	cat <<'EOS'
contents (Resource) when is_binary (Resource) ->
	{error, {undefined_resource, Resource}}.
EOS
) >./.generated/mosaic_static_resources.erl

exit 0
