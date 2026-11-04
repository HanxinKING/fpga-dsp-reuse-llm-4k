"""PS-side agent tools. Repository contents are data, never executed here.

Imports and capability inspection are read-only. Only git_clone creates the
workspace; the board's raw SSD weight/session layout is not a filesystem.
"""
from pathlib import Path
import os
import re
import shutil
import signal
import stat
import subprocess
import tempfile
import threading
import time
from urllib.parse import unquote, urlsplit

ROOT = Path('/opt/q9-workspaces')
PRIVATE_GIT = Path('/tmp/q9-agent/tools/git')
WINDOWS_RUN = r'F:\.codex\background\bin\run.exe'
MAX_OUTPUT = 12000
MAX_ERROR = 4000
CLONE_TIMEOUT = 120
_CLONE_LOCK = threading.Lock()
_NAMES = ('camera_capture', 'linux_query', 'git_clone', 'git_status',
          'read_file', 'list_directory')


def _git_runtime():
    configured = os.environ.get('Q9_GIT_RUNTIME')
    if configured:
        prefix = Path(configured)
        if (prefix / 'usr/bin/git').is_file():
            return str(prefix / 'usr/bin/git'), prefix
    installed = shutil.which('git')
    if installed:
        return installed, None
    for prefix in (Path('/opt/q9-agent-tools/git'), Path('/opt/q9-agent-tools'), PRIVATE_GIT):
        private = prefix / 'usr/bin/git'
        if private.is_file():
            return str(private), prefix
    return None, None


def capabilities():
    """Metadata only: no subprocess, network request, or directory creation."""
    git, private = _git_runtime()
    return dict(source='ps-linux', tools=list(_NAMES),
                workspace=str(ROOT), workspace_exists=ROOT.is_dir(),
                git_installed=bool(git), git_executable=git,
                git_runtime='private' if private else 'system' if git else None,
                git_url_policy='HTTPS repository URLs without embedded credentials',
                git_clone_timeout_seconds=CLONE_TIMEOUT,
                max_file_chars=50000, max_directory_entries=200)


def _environment(private=None):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith('GIT_')}
    env.update(GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='never',
               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
               GIT_HTTP_LOW_SPEED_LIMIT='1024', GIT_HTTP_LOW_SPEED_TIME='20',
               GIT_LFS_SKIP_SMUDGE='1')
    if private:
        env.update(GIT_EXEC_PATH=str(private / 'usr/lib/git-core'),
                   GIT_TEMPLATE_DIR=str(private / 'usr/share/git-core/templates'),
                   GIT_SSL_CAINFO=str(private / 'ca-bundle.crt'))
        env['LD_LIBRARY_PATH'] = ':'.join(str(private / item) for item in (
            'usr/lib/aarch64-linux-gnu', 'lib/aarch64-linux-gnu', 'usr/lib', 'lib'))
    return env


def _output(stream, maximum):
    size = stream.tell()
    stream.seek(max(0, size - maximum * 4))
    value = stream.read().decode('utf-8', errors='replace')
    return value[-maximum:], size > maximum * 4 or len(value) > maximum


def _stop(process):
    if os.name == 'posix':
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    else:
        process.kill()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass


def _run_git(arguments, cwd, timeout=10):
    git, private = _git_runtime()
    if not git:
        return dict(exit_code=None, stdout='', stderr='',
                    error='PS Git 未安装；未执行命令', timed_out=False)
    argv = [git, '-c', 'credential.helper=', '-c', 'core.hooksPath=' + os.devnull,
            '-c', 'core.fsmonitor=false', '-c', 'protocol.allow=never',
            '-c', 'protocol.https.allow=always', '-c', 'protocol.file.allow=never',
            '-c', 'protocol.ext.allow=never', *arguments]
    kwargs = dict(cwd=str(cwd), env=_environment(private), stdin=subprocess.DEVNULL)
    command = argv
    if os.name == 'nt':
        command = [WINDOWS_RUN, '--cwd', str(cwd), '--', *argv]
        kwargs['creationflags'] = subprocess.CREATE_NO_WINDOW
    else:
        kwargs['start_new_session'] = True
    started = time.monotonic()
    # File-backed stdout/stderr keep process output out of unbounded RAM buffers.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        try:
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr, **kwargs)
        except OSError as error:
            return dict(exit_code=None, stdout='', stderr='', error=str(error), timed_out=False)
        timed_out = False
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            _stop(process)
        out, out_cut = _output(stdout, MAX_OUTPUT)
        err, err_cut = _output(stderr, MAX_ERROR)
        result = dict(exit_code=process.returncode, stdout=out, stderr=err,
                      truncated=out_cut or err_cut, timed_out=timed_out,
                      elapsed_seconds=round(time.monotonic() - started, 3))
        if timed_out:
            result['error'] = 'Git 执行超时'
        elif process.returncode:
            result['error'] = 'Git 退出码 ' + str(process.returncode)
        return result


def _workspace():
    if ROOT.is_symlink():
        raise ValueError('工具工作目录不能是符号链接')
    return ROOT.resolve()


def _path(value):
    if not isinstance(value, str) or not value.strip() or '\0' in value or len(value) > 4096:
        raise ValueError('path/directory 必须是非空路径字符串')
    root = _workspace()
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    # Resolve existing links before opening; links outside the workspace fail.
    path = path.resolve()
    try:
        path.relative_to(root)
    except ValueError:
        raise ValueError('文件工具仅允许访问 ' + str(ROOT)) from None
    return path


def _url(value):
    if not isinstance(value, str):
        raise ValueError('url 必须是字符串')
    value = value.strip()
    if len(value) > 4096 or any(char.isspace() or ord(char) < 32 for char in value):
        raise ValueError('url 必须是合法 HTTPS 仓库地址')
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError:
        raise ValueError('url 必须是合法 HTTPS 仓库地址') from None
    if (parsed.scheme.lower() != 'https' or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or not parsed.path.strip('/') or parsed.fragment):
        raise ValueError('仅支持无内嵌账号或令牌的 HTTPS 仓库地址')
    repo = unquote(parsed.path.rstrip('/').rsplit('/', 1)[-1])
    if repo.lower().endswith('.git'):
        repo = repo[:-4]
    repo = re.sub(r'[^A-Za-z0-9_.-]', '-', repo)[:100]
    if not repo or repo in ('.', '..'):
        raise ValueError('仓库名称无效')
    return value, repo


def _head(path):
    result = _run_git(['-C', str(path), 'rev-parse', '--verify', 'HEAD'], path)
    value = result['stdout'].strip()
    return value if result['exit_code'] == 0 and re.fullmatch(r'[0-9a-fA-F]{40,64}', value) else None


def _readmes(path):
    return [str(item) for item in sorted(path.iterdir(), key=lambda p: p.name.lower())
            if item.name.lower().startswith('readme') and item.is_file()
            and not item.is_symlink()][:20]


def _clone(arguments):
    url, repo = _url(arguments['url'])
    destination = _path(arguments.get('directory', repo))
    # Inspect installation before any mkdir. No install or download fallback.
    if not _git_runtime()[0]:
        return dict(ok=False, url=url, path=str(destination), head=None,
                    readme_candidates=[], exit_code=None, error='PS Git 未安装；未执行克隆')
    if not _CLONE_LOCK.acquire(blocking=False):
        return dict(ok=False, exit_code=None, error='另一个 Git 克隆正在执行')
    try:
        if destination.exists() or destination.is_symlink():
            return dict(ok=False, status='already_exists', path=str(destination),
                        exit_code=None, error='目标目录已存在，保留原内容')
        root = _workspace()
        root.mkdir(parents=True, exist_ok=True)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.clone-', dir=root) as pending:
            work = Path(pending) / 'repository'
            result = _run_git(['clone', '--depth', '1', '--single-branch', '--no-tags',
                               '--no-recurse-submodules', '--template=', '--', url, str(work)],
                              root, CLONE_TIMEOUT)
            result.update(url=url, path=str(destination), head=None, readme_candidates=[])
            if result['exit_code'] != 0 or result.get('timed_out') or result.get('error'):
                result['ok'] = False
                return result
            if not work.is_dir():
                result.update(ok=False, error='Git 返回成功但没有创建仓库目录')
                return result
            # Preserve a destination created while clone was running as well.
            if destination.exists() or destination.is_symlink():
                result.update(ok=False, error='目标目录已存在，保留原内容')
                return result
            work.rename(destination)
            result.update(ok=True, status='cloned', head=_head(destination),
                          readme_candidates=_readmes(destination))
            return result
    finally:
        _CLONE_LOCK.release()


def _git_status(arguments):
    path = _path(arguments['path'])
    if not path.is_dir():
        return dict(ok=False, path=str(path), exit_code=None, error='仓库目录不存在')
    result = _run_git(['-C', str(path), 'status', '--short', '--branch', '--untracked-files=normal'], path)
    result.update(ok=result['exit_code'] == 0 and not result.get('error'), path=str(path))
    if result['ok']:
        result['head'] = _head(path)
    return result


def _read_file(arguments):
    path = _path(arguments['path'])
    maximum = arguments.get('max_chars', 12000)
    if not isinstance(maximum, int) or isinstance(maximum, bool) or not 1 <= maximum <= 50000:
        raise ValueError('max_chars 必须是 1 到 50000 的整数')
    if not path.is_file():
        return dict(ok=False, path=str(path), error='文件不存在或不是普通文件')
    with path.open('r', encoding='utf-8', errors='replace') as handle:
        content = handle.read(maximum + 1)
    return dict(ok=True, path=str(path), content=content[:maximum],
                truncated=len(content) > maximum, encoding='utf-8', max_chars=maximum)


def _list_directory(arguments):
    path = _path(arguments['path'])
    if not path.is_dir():
        return dict(ok=False, path=str(path), error='目录不存在')
    entries = []
    # Sort a bounded set rather than holding an arbitrarily large listing.
    with os.scandir(path) as iterator:
        for index, entry in enumerate(iterator):
            if index >= 200:
                return dict(ok=True, path=str(path), entries=sorted(entries, key=lambda x: x['name']),
                            truncated=True, max_entries=200)
            info = entry.stat(follow_symlinks=False)
            kind = ('symlink' if stat.S_ISLNK(info.st_mode) else 'directory' if stat.S_ISDIR(info.st_mode)
                    else 'file' if stat.S_ISREG(info.st_mode) else 'other')
            entries.append(dict(name=entry.name, type=kind, bytes=info.st_size))
    return dict(ok=True, path=str(path), entries=sorted(entries, key=lambda x: x['name']),
                truncated=False, max_entries=200)


def execute(name, arguments):
    """Return {name, ok, source:'ps-linux', result}; validation raises ValueError."""
    if not isinstance(name, str) or name not in _NAMES:
        raise ValueError('未知的 Agent 工具')
    if not isinstance(arguments, dict):
        raise ValueError('arguments 必须是 JSON 对象')
    required, optional = {
        'camera_capture': (set(), set()),
        'linux_query': ({'query'}, set()),
        'git_clone': ({'url'}, {'directory'}),
        'git_status': ({'path'}, set()),
        'read_file': ({'path'}, {'max_chars'}),
        'list_directory': ({'path'}, set()),
    }[name]
    if not required <= arguments.keys() or arguments.keys() - required - optional:
        raise ValueError(name + ' 参数字段不匹配')
    try:
        if name == 'camera_capture':
            import ps_camera
            try:
                result = ps_camera.capture()
            except ps_camera.CameraError as error:
                result = dict(ok=False, error=str(error), status=error.status)
        elif name == 'linux_query':
            if not isinstance(arguments['query'], str):
                raise ValueError('query 必须是字符串')
            import ps_linux_tools
            result = ps_linux_tools.execute(arguments['query'])
            result['ok'] = all(row.get('exit_code') == 0 and not row.get('timed_out')
                               for row in result.get('commands', []))
        else:
            result = {'git_clone': _clone, 'git_status': _git_status, 'read_file': _read_file,
                      'list_directory': _list_directory}[name](arguments)
    except (OSError, subprocess.SubprocessError) as error:
        result = dict(ok=False, error=str(error))
    return dict(name=name, ok=result.get('ok', True), source='ps-linux', result=result)
