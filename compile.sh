#!/bin/sh
#|| goto :windows_detected
{ # put the whole thing in a block so as not to behave weirdly if interrupted
set -e

# 全局变量：
# CHOICE_BUILDTYPE  - “Release” 或 “Debug”。
# CHOICE_THREADS    - 数值，make 命令要使用的线程数。
# CHOICE_BRANCH     - 要使用的分支。目前锁定为 “master”。
# STATE_INTERACTIVE - 如果是交互式运行则为 1，否则为 0。
# STATE_NEW         - 是否是首次运行。如果是 1，则尚未存在 GIT 仓库。否则为 0。

# Constants:
DEFAULT_BUILDTYPE="Release" # Other options: "Debug"
DEFAULT_BRANCH="master"     # Other options: None currently
DEFAULT_THREADS=1

# Constants not modifiable through command line:
UPSTREAM_REPO="origin"
UPSTREAM_LINK="https://github.com/Q2297045667/cuberite.git"

#=================== Error functions ===================


errorCompile ()
{
	echo
	echoInt "-----------------"
	echo "编译失败。失败的命令:"
	echo "$@"
	exit 1
}

errorGit ()
{
	echo
	echoInt "-----------------"
	echo "代码获取失败。（请检查你的网络连接）。失败的命令:"
	echo "$@"
	exit 2
}

errorDependencies ()
{
	# The error messages are complex and OS-dependant, and are printed in the dependencies section before this is called.
	exit 3
}

errorArguments ()
{
	echo "用法：./compile.sh [选项]"
	echo "编译 Cuberite。如果需要，会更新 GIT 仓库，如果仓库不存在，则会下载。"
	echo "如果没有指定一个或多个选项，则以交互方式运行。"
	echo
	echo "选项："
	echo "  -m  编译模式。可以是\"Release\"或\"Debug\"。默认为\"$DEFAULT_BUILDTYPE\""
	echo "  -t  编译时使用的线程数"
	echo "      如果未指定，则默认使用$DEFAULT_THREADS个线程。"
	echo "      特殊值AUTO会尝试将编译线程数设置为CPU线程数。"
	echo "  -b  要编译的分支。（目前未使用，固定为MASTER）"
	echo "  -n yes: 禁用交互模式。与其他参数组合时无需此选项。"
	echo "          不与其他参数一起使用时，按默认设置进行构建。"
	echo "  -d yes: 干运行。打印选定的设置并退出"
	echo
	echo "使用示例："
	echo "  ./compile.sh"
	echo "  ./compile.sh -m Debug"
	echo "  ./compile.sh -m Release -t 2"
	echo
	echo "返回代码：（非0返回值会附带有用的stderr信息）"
	echo "0 - 成功              - 成功！代码已更新并编译"
	echo "1 - 编译失败         - cmake、make或源代码问题"
	echo "2 - 代码获取失败      - 网络问题或（极少数情况下）git问题"
	echo "3 - 缺少依赖项       - 缺少某些编译工具"
	echo "4 - 参数错误          - 传递了错误的命令行参数"
	echo "5 - 用户输入错误      - 交互模式中输入了无效的用户输入"
	echo "6 - 其他              - 上述未列出的错误"
	exit 4
}

errorInput ()
{
	echo
	echoInt "-----------------"
	echo "未识别的用户输入"
	echo "$@"
	exit 5
}

errorOther ()
{
	echo
	echoInt "-----------------"
	echo "$@"
	exit 6
}


#=================== Echo functions ===================


echoInt () # echo only if interactive mode.
{
	if [ $STATE_INTERACTIVE -eq 1 ]; then
		echo "$1"
	fi
}

echoErr () # Echo to stderr.
{
	echo "$1" 1>&2
}


#=================== Commandline Parsing ===================


STATE_INTERACTIVE=1 # Interactive, unless one or more command line options are passed.
while getopts ":m:t:b:d:n:" name; do
	value=$OPTARG
	STATE_INTERACTIVE=0
	case "$name" in
	m)
		if [ ! -z "$CHOICE_BUILDTYPE" ]; then errorArguments; fi # Argument duplication.
		if [ "$value" = "Debug" ] || [ "$value" = "Release" ]; then
			CHOICE_BUILDTYPE="$value"
		else
			errorArguments
		fi
	;;
	t)
		if [ ! -z "$CHOICE_THREADS" ]; then errorArguments; fi # Argument duplication.
		if [ "$value" -gt 0 ] 2>/dev/null || [ "$value" = "AUTO" ]; then # If a positive integer or the special value "AUTO".
			CHOICE_THREADS="$value"
		else
			errorArguments
		fi
	;;
	b)
		if [ ! -z "$CHOICE_BRANCH" ]; then errorArguments; fi # Argument duplication.
		CHOICE_BRANCH=1 # Only used for dupe checking, overridden below.
		echoErr "警告：当前未使用 -b 选项，该选项被忽略了"
	;;
	d)
		if [ ! -z "$DRY_RUN" ]; then errorArguments; fi # Argument duplication.
		DRY_RUN="yes"
	;;
	n)
		if [ "$dummy" = "1" ]; then errorArguments; fi # Argument duplication.
		dummy=1 # we just want to disable interactive mode, passing an argument already did this. No need to do anything.
	;;
	*)
		errorArguments
	;;
	esac
done

if [ -z "$DRY_RUN" ]; then DRY_RUN="no"; fi

#=================== Dependency checks and greeting ===================


# Do we already have a repo?
checkCuberiteDir ()
{
	[ -d .git ] && [ -f easyinstall.sh ] && [ -f src/BlockArea.cpp ] # A good enough indicator that we're in the Cuberite git repo.
}

STATE_NEW=1
if checkCuberiteDir; then # Check if we're in the Cuberite directory...
	STATE_NEW=0
elif [ -d cuberite ]; then # If there's a directory named "cuberite"...
	cd cuberite
	if checkCuberiteDir; then # Check if we're in the Cuberite directory...
		STATE_NEW=0
	else
		errorOther "存在一个名为 cuberite 的目录，但其中不存在任何 Cuberite 资源。请在其他位置运行脚本，或者移动/删除该目录"
	fi

fi

if [ $STATE_NEW -eq 0 ]; then
	echoInt "检测到 Cuberite 仓库。这将加速整个编译过程，尤其是如果您之前已经编译过"
fi

# Echo: Greetings.
echoInt "

你好，这个脚本将下载并编译 Cuberite。
在后续运行中，它将更新 Cuberite。
编译和下载将在当前目录中进行。
如果你正在更新，你应该运行：<Cuberite路径>/compile.sh
从源代码编译需要时间，但它通常会生成更快的可执行文件。
如果你更喜欢现成的二进制文件，或者想了解更多，
请访问：https://cuberite.org/"

doDependencyCheck()
{
	MISSING_PACKAGES=""

	# Most distros have the following default compiler names.
	GCC_EXE_NAME="g++"
	CLANG_EXE_NAME="clang"
	COMPILER_PACKAGE_NAME="gcc g++"

	# Most distros have the following package and executable names.
	# Left side: Executable Name, Right side: Package Name. Note that this is SPACE delimited now, unlike in the past.
	PROGRAMS='git git
	make make
	cmake cmake'

	# If any OS deviates from the defaults, we detect the OS here, and change PROGRAMS, COMPILER_PACKAGE_NAME, etc. as needed.

	# Fedora, CentOS, RHEL, Mageia, openSUSE, Mandriva.
	if (rpm --help > /dev/null 2> /dev/null); then
		COMPILER_PACKAGE_NAME="gcc-c++"
	fi

	# Make sure at least one compiler exists.
	GCC_EXISTS=0
	CLANG_EXISTS=0
	$GCC_EXE_NAME --help > /dev/null 2> /dev/null && GCC_EXISTS=1
	$CLANG_EXE_NAME --help > /dev/null 2> /dev/null && CLANG_EXISTS=1
	if [ "$GCC_EXISTS" -eq 0 ] && [ "$CLANG_EXISTS" -eq 0 ]; then
		MISSING_PACKAGES=" $COMPILER_PACKAGE_NAME"
	fi

	# Depdendency check.
	checkPackages ()
	{
		echo "$PROGRAMS" | while read line; do
			EXE_NAME=`echo "$line" | cut -f 1 -d " "`
			PACKAGE_NAME=`echo "$line" | cut -f 2 -d " "`
			command -v $EXE_NAME > /dev/null 2> /dev/null || printf %s " $PACKAGE_NAME"
		done
	}
	MISSING_PACKAGES="$MISSING_PACKAGES`checkPackages`"
	missingDepsExit ()
	{
		if [ "$1" != "" ]; then
			echoErr "你可以通过以下方式安装缺少的依赖项:"
			echoErr "$1"
		fi
		echoErr
		echoErr "请安装依赖项，然后回来继续"
		echoErr
		errorDependencies
	}

	if [ "$MISSING_PACKAGES" != "" ]; then
		echoInt
		echoInt "-----------------"
		echoErr "缺少编译所需的依赖项:"
		echoErr $MISSING_PACKAGES
		echoErr

		# apt-get guide.
		apt-get --help > /dev/null 2> /dev/null && \
		missingDepsExit "apt-get install$MISSING_PACKAGES"

		# dnf guide.
		dnf --help > /dev/null 2> /dev/null && \
		missingDepsExit "dnf install$MISSING_PACKAGES"

		# zypper guide.
		zypper --help > /dev/null 2> /dev/null && \
		missingDepsExit "zypper install$MISSING_PACKAGES"

		# pacman guide.
		pacman --help > /dev/null 2> /dev/null && \
		missingDepsExit "pacman -S$MISSING_PACKAGES"

		# urpmi guide.
		urpmi --help > /dev/null 2> /dev/null && \
		missingDepsExit "urpmi$MISSING_PACKAGES"

		missingDepsExit ""
	fi
}
doDependencyCheck


#=================== Choice: Branch (Currently unused and simply skipped) ===================


# Bypass Branch choice and choose master. Because it's the only branch right now.
CHOICE_BRANCH=$DEFAULT_BRANCH

### Inactive code start. ###
inactiveCode ()
{

echo "
你可以选择以下三个分支:
* (S)稳定版:    如果你想使用最可靠的服务器
               请选择稳定分支.

* (T)测试版:    测试分支的稳定性稍差,
               但使用它并向我们报告问题对我们帮助很大！

* (D)开发版:    三个分支中最不稳定的一个
               （主分支）如果你想尝试新的、最新的功能,
               请选择开发分支.
* (E)实验性：    最新的，也是最不稳定的。
"


printf %s "选择分支（s/t/d/e）: "
read CHOICE_BRANCH
case $CHOICE_BRANCH in
	s|S)
		errorOther "我们还没有稳定分支，请使用测试分支，抱歉。"
		;;
	t|T)
		CHOICE_BRANCH="testing"
		;;
	d|D)
		CHOICE_BRANCH="master"
		;;
  e|E)
		CHOICE_BRANCH="experimental"
		;;
	*)
		errorInput
		;;
esac

}
### Inactive code end. ###


#=================== Choice: Compile mode ===================


if [ $STATE_INTERACTIVE -eq 1 ]; then
	echo "
	选择编译模式:
	* (R)发布版: 正常编译。生成最快的构建版本。

	* (D)调试版: 以调试模式编译。
		      使你的控制台和崩溃信息更加详细。
		      比发布模式稍慢。
		      如果你计划通过报告错误来帮助开发，这是首选。

	"

	printf %s "选择编译模式：(r/d)(默认: \"$DEFAULT_BUILDTYPE\"): "
	read CHOICE_BUILDTYPE
	case $CHOICE_BUILDTYPE in
		d|D)
			CHOICE_BUILDTYPE="Debug"
			;;
		r|N)
			CHOICE_BUILDTYPE="Release"
			;;
	esac
fi

if [ -z "$CHOICE_BUILDTYPE" ]; then # No buildtype specified.
	CHOICE_BUILDTYPE="$DEFAULT_BUILDTYPE"
fi


#=================== Choice: Thread amount ===================



numberOfThreads()
{
	KERNEL=`uname -s`

	if [ "$KERNEL" = "Linux" ] || [ "$KERNEL" = "Darwin" ]; then
		echo `getconf _NPROCESSORS_ONLN`
	elif [ "$KERNEL" = "FreeBSD" ]; then
		echo `getconf NPROCESSORS_ONLN`
	else
		echo "unknown"
	fi
}

CPU_THREAD_COUNT=`numberOfThreads`

if [ $STATE_INTERACTIVE -eq 1 ]; then
	echo ""
	echo "选择编译线程的数量"

	if [ "$CPU_THREAD_COUNT" = "unknown" ]; then
		echo "无法检测到 CPU 线程的数量"
	elif [ "$CPU_THREAD_COUNT" -eq 1 ]; then
		echo "你有 1 个线程"
	else
		echo "你有 $CPU_THREAD_COUNT 个 CPU 线程"
	fi

	echo "如果你有足够的 RAM，选择与你的 CPU 线程数相同的线程数是明智的。 "
	echo "否则请选择较低的线程数。旧款树莓派应该选择 1。如果不确定的话直接选择 1。"
	printf %s "请输入要使用的编译线程数 (默认: $DEFAULT_THREADS): "
	read CHOICE_THREADS
fi

if [ -z "$CHOICE_THREADS" ] 2> /dev/null; then
	CHOICE_THREADS="$DEFAULT_THREADS"
elif [ "$CHOICE_THREADS" = "AUTO" ] 2> /dev/null; then
	if [ $CPU_THREAD_COUNT = "unknown" ]; then
		CHOICE_THREADS="$DEFAULT_THREADS"
		echo "警告：无法检测到线程数。将使用默认值（$DEFAULT_THREADS）" >&2
	else
		CHOICE_THREADS="$CPU_THREAD_COUNT"
	fi
elif [ "$CHOICE_THREADS" -lt 0 ] 2> /dev/null; then
	errorInput
fi

#=================== Print settings summary  ===================


if [ "$STATE_NEW" = 1 ]; then
	previousCompilation="未检测到。我们假设这是第一次运行 compile.sh"
else
	previousCompilation="已检测到。这将使获取和编译过程更快"
fi

THREAD_WARNING=""
if [ "$CPU_THREAD_COUNT" != "unknown" ] && [ "$CPU_THREAD_COUNT" -lt "$CHOICE_THREADS" ]; then
	THREAD_WARNING=" - 警告：分配的线程数超过了CPU线程数"
fi

echo ""
echoInt "#### 设置摘要 ####"
echo "构建类型：           " "$CHOICE_BUILDTYPE"
echo "使用分支：           " "$CHOICE_BRANCH" "(目前唯一的选择)"
echo "编译线程：           " "$CHOICE_THREADS$THREAD_WARNING"
echo "核心数量：           " "$CPU_THREAD_COUNT"
echo "上次数据：           " "$previousCompilation"
echo "上游链接：           " "$UPSTREAM_LINK"
echo "上游仓库：           " "$UPSTREAM_REPO"

if [ "$DRY_RUN" = "yes" ]; then
	echo "这是一个比较运行"
	exit 0;
fi

# Ask the user's permission to connect to the net.
if [ $STATE_INTERACTIVE -eq 1 ]; then
	echo
	echo "按下ENTER键后，脚本将连接到 $UPSTREAM_LINK"
	echo "以检查更新和/或获取代码。之后它将编译你的程序。"
	echo "如果你之前编译过，请确保你在正确的目录中，并且 上次数据 被检测到。"
	printf $s "按 ENTER 键继续... "
	read dummy
fi


#=================== Code download / update via git ===================


echoInt
echoInt " --- 从 $CHOICE_BRANCH 分支下载 Cuberite 的源代码..."


if [ $STATE_NEW -eq 1 ]; then
	# Git: Clone.
	echo " --- 看起来这是你的第一次运行，正在克隆整个代码库..."
	git clone  --depth 1 "$UPSTREAM_LINK" -b "$CHOICE_BRANCH" || errorGit "git clone  --depth 1 $UPSTREAM_LINK -b $CHOICE_BRANCH"
	cd cuberite
else
	# Git: Fetch.
	echo " --- 正在更新 $CHOICE_BRANCH 分支..."
	git fetch "$UPSTREAM_REPO" "$CHOICE_BRANCH" || errorGit "git fetch $UPSTREAM_REPO $CHOICE_BRANCH"
	git checkout "$CHOICE_BRANCH" || errorGit "git checkout $CHOICE_BRANCH"
	git merge "$UPSTREAM_REPO"/"$CHOICE_BRANCH" || errorGit "git merge $UPSTREAM_REPO/$CHOICE_BRANCH"
fi

# Git: Submodules.
echo " --- 正在更新子模块..."
git submodule sync
git submodule update --init


#=================== Compilation via cmake and make ===================


# Cmake.
echo " --- 正在运行 cmake..."
if [ ! -d build-cuberite ]; then mkdir build-cuberite; fi
cd build-cuberite
cmake .. -DCMAKE_BUILD_TYPE="$CHOICE_BUILDTYPE" || errorCompile "cmake .. -DCMAKE_BUILD_TYPE=$CHOICE_BUILDTYPE"


# Make.
echo " --- 正在编译..."
make -j "$CHOICE_THREADS" || errorCompile "make -j $CHOICE_THREADS"
echo


#=================== Print success message ===================


cd Server
echo
echo "-----------------"
echo "编译完成！"
echo
echo "Cuberite 已准备好，位于:"
echo "$PWD/Cuberite"

cd ../..
echo "
你可以随时通过执行以下命令来更新 Cuberite:
$PWD/compile.sh

祝你玩得开心 :)"
exit 0


#=================== Windows fallback ===================


# Called via hack in line 2.
:windows_detected
@echo off
cls
echo “这个脚本目前还不支持Windows，抱歉。”
echo “你仍然可以从以下网址下载Windows的二进制文件：https://cuberite.org/ ”
echo “你也可以手动为Windows编译。详情请查看：https://github.com/cuberite/cuberite”
rem windows_exit
goto :EOF
}
