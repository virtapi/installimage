# installimage - Style Guide

---

## Contents
+ [Indentation Guidelines](#indentation-guidelines)
+ [Multiline Output to File](#multiline-output-to-file)
+ [Functions](#functions)
+ [Escaping](#escaping)
+ [Preferred Usage of Bash Builtins](#preferred-usage-of-bash-builtins)
+ [Multiple Parameter Validation](#multiple-parameter-validation)
+ [Brackets Notation](#brackets-notation)
+ [Inspiration](#inspiration)

---

## Indentation Guidelines
we use two whitespaces for Indentation, and no hard tabs. This results in the following vim settings:
```
set tabstop=2
set shiftwidth=2
set expandtab
set softtabstop=2
```

## Multiline Output to File
Group the output of multiple commands with braces and redirect this once into a file. Here is a bad example:
```bash
echo "### $COMPANY - installimage" > "$CONFIGFILE"
echo "# Loopback device:" >> "$CONFIGFILE"
echo "auto lo" >> "$CONFIGFILE"
echo "iface lo inet loopback" >> "$CONFIGFILE"
echo "" >> "$CONFIGFILE"
```

The `{` and the `}` have to be in own lines and the content between them indented by two spaces. Here is another bad example:
```bash
{	echo "### $COMPANY - installimage"
echo "# Loopback device:"
echo "auto lo"
echo "iface lo inet loopback"
echo "" } > "$CONFIGFILE"
```

This good example is:
```bash
{
	echo "### $COMPANY - installimage"
	echo "# Loopback device:"
	echo "auto lo"
	echo "iface lo inet loopback"
	echo ""
} > "$CONFIGFILE"
```

## Functions
Functions should be pure if possible, e.g. the same input produces the same output and they should not access global variables.
This makes reasoning about correctness much easier.

## Escaping
We don't want dirty escaping for variables in `echo`, we should prefer printf in these cases, here is a bad example:
```bash
echo -e "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"$2\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"$1\"" >> $UDEVFILE
```

and here a good one:
```bash
printf 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="%s", ATTR{dev_id}=="0x0", ATTR{type}=="1", KERNEL=="eth*", NAME="%s"\n' "$2" "$1" >> "$UDEVFILE"
```

## Preferred Usage of bash builtins
For security and performance reasons we should use bash builtins whereever possible. Bad example for iterations:
```bash
for i in $(seq 1 $COUNT_DRIVES) ; do
	if [ $SWRAID -eq 1 -o $i -eq 1 ] ;  then
		local disk="$(eval echo "\$DRIVE"$i)"
		execute_chroot_command "grub-install --no-floppy --recheck $disk 2>&1"
	fi
done
```

and a good example:
```bash
for ((i=1; i<="$COUNT_DRIVES"; i++)); do
	if [ "$SWRAID" -eq 1 ] || [ "$i" -eq 1 ] ;  then
		local disk; disk="$(eval echo "\$DRIVE"$i)"
		execute_chroot_command "grub-install --no-floppy --recheck $disk 2>&1"
	fi
done
```

## Multiple Parameter Validation
Always use seperate testcases for params, bad example:
```bash
if [ "$1" -a "$2" ]; then
```

good example:
```bash
if [ -n "$1" ] && [ -n "$2" ]; then
```

## Brackets Notation
We want to avoid useless whitespace in general, for example in brackets. here is a bad awk example:
```bash
awk '{ print $2 }'
```

and the correct one:
```bash
awk '{print $2}'
```

## Inspiration
This is loosely based on:
+ [Bash Hackers Style Guide](http://wiki.bash-hackers.org/scripting/style)
+ [Googles Shell Style Guide](https://google.github.io/styleguide/shell.xml)
