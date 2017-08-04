#!/bin/bash

# Process command line options
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -u|--username)
    USERNAME="$2"
    shift
    ;;
    -p|--password)
    PASSWORD="$2"
    shift # past argument
    ;;
    -d|--db-name)
    DB_NAME="$2"
    shift # past argument
    ;;
    -a|--archive-dir)
    ARCHIVE_DIR=$(readlink -f "$2") 
    exitcode=$?
    if [ $exitcode -ne 0 ]
      then
        echo "Error: archive directory does not exist"
        exit $exitcode
    fi
    shift # past argument
    ;;
    -o|--output-dir)
    OUTPUT_DIR=$(readlink -f "$2")
    if [ $exitcode -ne 0 ]
      then
        echo "Error: output directory does not exist"
        exit $exitcode
    fi
    shift # past argument
    ;;
    -h|--help)
    echo "Reserves Redirect!"
    echo "complaints/bug reports go to Ryan Sablosky <gsablosky@bard.edu>"
    echo "released into the public domain"
    echo "----------------"
    echo ""
    echo "Options:"
    echo "	-u, --username		mysql username with read access to the db"
    echo "	-p, --password		mysql password"
    echo "	-d, --db-name		reserves direct database name"
    echo "	-a, --archive-dir	location of archive files"
    echo "	-o, --output-dir	directory to copy files to"
    echo "	-h, --help		this help, the stuff you're reading right now"
    exit 0
    ;;
    *)
    echo "Unknown option $key"
    exit 64 
    ;;
esac
shift # past argument or value
done

if [ -z $USERNAME ] 
then
    echo "Error: please provide a username using the -u command-line option"
    exit 64
fi

if [ -z $PASSWORD ] 
then
    echo "Error: please provide a password using the -p command-line option"
    exit 64
fi

if [ -z $DB_NAME ]
then
    echo "Error: please provide the name for the Reserves Direct database."
    exit 64
fi

if [ -z $ARCHIVE_DIR ] || [ ! -d $ARCHIVE_DIR ] 
then
    echo "Error: please provide the path to the archive location using the -a command-line option"
    exit 64
fi

if [ -z $OUTPUT_DIR ] || [ ! -d $OUTPUT_DIR ] 
then
    echo "Error: please provide a place to copy the files using the -o command-line option"
    exit 64
fi

# The query we run
QUERY="USE $DB_NAME;

SELECT u.last_name, u.first_name, ca.course_name, ci.term, ci.year, i.title, i.url
FROM items i
INNER JOIN reserves r ON i.item_id = r.item_id
INNER JOIN course_instances ci ON r.course_instance_id = ci.course_instance_id
INNER JOIN course_aliases ca ON ci.course_instance_id = ca.course_instance_id
INNER JOIN access a ON a.alias_id = ca.course_alias_id
INNER JOIN users u ON a.user_id = u.user_id
WHERE a.permission_level = 3 AND i.url IS NOT NULL AND i.url NOT LIKE \"http://library.bard.edu%\"
ORDER BY ci.year;
"

echo "Running query:"
echo $QUERY
echo "----------------"

RESULTS="$(mysql -B --host=localhost --user=$USERNAME --password="$PASSWORD" -e "$QUERY")"

# Check exit status
exitcode="$?"
if [ $exitcode -ne 0 ]
then
	printf "Error [%d] from query! Check your parameters and query\n" $exitcode
	exit $?
fi

echo "Done."

# Process files. This tells read to break on tabs 
echo "Processing files..."
while IFS=$'\t' read -r -a rows
do
	LAST_NAME=${rows[0]}
	FIRST_NAME=${rows[1]}
	COURSE_NAME=${rows[2]}
	COURSE_TERM=${rows[3]}
	COURSE_YEAR=${rows[4]}
	FILE_TITLE=${rows[5]}
	ARCHIVE_URL=${rows[6]}

	# Prep output path	
	NAME="$LAST_NAME, $FIRST_NAME"
	OUTPUT_PATH_COMPONENTS=("$OUTPUT_DIR" "$NAME" "$COURSE_NAME" "$COURSE_TERM $COURSE_YEAR");
	printf -v OUTPUT_PATH '/%s/' "${OUTPUT_PATH_COMPONENTS[@]%/}"
	OUTPUT_PATH=$(readlink -m "$OUTPUT_PATH")
	mkdir -p "$OUTPUT_PATH"
	
	# Handle URL resources
	if [[ $ARCHIVE_URL =~ http(s?)\:\/\/.* ]]
	then 	
		URL_PATH="$OUTPUT_PATH/links.html"
		if [ ! -e "$URL_PATH" ]
		then
			cat > "$URL_PATH" <<EOF
<html>
<head>
<title>External resources for $COURSE_NAME, $COURSE_TERM, $COURSE_YEAR</title>
</head>
<body>
<h1>External resources for $COURSE_NAME, $COURSE_TERM, $COURSE_YEAR</h1>
<ul>
EOF
		fi
		
		echo "<li><a href=\"$ARCHIVE_URL\">$FILE_TITLE</a></li>" >> "$URL_PATH"
		continue
	fi
	
	# get output extension
	filename=$(basename "$ARCHIVE_URL")
	extension="${filename##*.}"
	
	# Build up components of the archive & output path
	ARCHIVE_FILE_COMPONENTS=("$ARCHIVE_DIR" "$ARCHIVE_URL");
	

	printf -v ARCHIVE_FILE '/%s' "${ARCHIVE_FILE_COMPONENTS[@]%/}"
	OUTPUT_FILE="$OUTPUT_PATH/$FILE_TITLE.$extension"
	
	ARCHIVE_FILE=$(readlink -m "$ARCHIVE_FILE")
	OUTPUT_FILE=$(readlink -m "$OUTPUT_FILE")

	cp "$ARCHIVE_FILE" "$OUTPUT_FILE"
done <<< "$RESULTS"
echo "Done!"
