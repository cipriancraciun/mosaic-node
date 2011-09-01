#!/dev/null

if ! test "${#}" -eq 0 ; then
	echo "[ee] invalid arguments; aborting!" >&2
	exit 1
fi

"${_workbench}/scripts/publish"
"${_workbench}/scripts/publish-boot"

"${_workbench}/../mosaic-components-rabbitmq/scripts/publish"
"${_workbench}/../mosaic-components-riak-kv/scripts/publish"
"${_workbench}/../mosaic-components-httpg/scripts/publish"

if test "${_mosaic_do_all_java:-false}" == true ; then
	"${_workbench}/../mosaic-java-components/components-container/scripts/publish"
	"${_workbench}/../mosaic-java-platform/mosaic-mvn/mosaic-cloudlet/scripts/publish"
	"${_workbench}/../mosaic-java-platform/mosaic-mvn/mosaic-driver/scripts/publish"
fi

if test "${_mosaic_do_all_examples:-false}" == true ; then
	"${_workbench}/../mosaic-examples-realtime-feeds/backend/scripts/publish"
	# "${_workbench}/../mosaic-examples-realtime-feeds-java/scripts/publish"
fi

exit 0
