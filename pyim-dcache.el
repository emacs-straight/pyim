;;; pyim-dcache.el --- dcache tools for pyim.        -*- lexical-binding: t; -*-

;; * Header
;; Copyright (C) 2021 Free Software Foundation, Inc.

;; Author: Feng Shu <tumashu@163.com>
;; Maintainer: Feng Shu <tumashu@163.com>
;; URL: https://github.com/tumashu/pyim
;; Keywords: convenience, Chinese, pinyin, input-method

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:
;; * 代码                                                           :code:
(require 'cl-lib)
(require 'pyim-common)
(require 'pyim-dict)

(defgroup pyim-dcache nil
  "Dcache for pyim."
  :group 'pyim)

(defcustom pyim-dcache-directory (locate-user-emacs-file "pyim/dcache/")
  "一个目录，用于保存 pyim 词库对应的 cache 文件."
  :type 'directory
  :group 'pyim)

(defcustom pyim-dcache-backend 'pyim-dhashcache
  "词库后端引擎.负责缓冲词库并提供搜索词的算法.
可选项为 `pyim-dhashcache' 或 `pyim-dregcache'.
前者搜索单词速度很快,消耗内存多.  后者搜索单词速度较快,消耗内存少.

`pyim-dregcache' 速度和词库大小成正比.  当词库接近100M大小时,
在六年历史的笔记本上会有一秒的延迟. 这时建议换用 `pyim-dhashcache'.

注意：`pyim-dregcache' 只支持全拼和双拼输入法，不支持其它型码输入法."
  :type 'symbol)

(defvar pyim-dcache-auto-update t
  "是否自动创建和更新词库对应的 dcache 文件.

这个变量默认设置为 t, 如果有词库文件添加到 `pyim-dicts' 或者
`pyim-extra-dicts' 时，pyim 会自动生成相关的 dcache 文件。

一般不建议将这个变量设置为 nil，除非有以下情况：

1. 用户的词库已经非常稳定，并且想通过禁用这个功能来降低
pyim 对资源的消耗。
2. 自动更新功能无法正常工作，用户通过手工从其他机器上拷贝
dcache 文件的方法让 pyim 正常工作。")

;; ** Dcache API 调用功能
(defun pyim-dcache-call-api (api-name &rest api-args)
  "Get backend API named API-NAME then call it with arguments API-ARGS."
  ;; make sure the backend is load
  (unless (featurep pyim-dcache-backend)
    (require pyim-dcache-backend))
  (let ((func (intern (concat (symbol-name pyim-dcache-backend)
                              "-" (symbol-name api-name)))))
    (if (functionp func)
        (apply func api-args)
      (when pyim-debug
        (message "%S 不是一个有效的 dcache api 函数." (symbol-name func))
        ;; Need to return nil
        nil))))

;; ** Dcache 变量处理相关功能
(defun pyim-dcache-init-variables ()
  "初始化 dcache 缓存相关变量."
  (pyim-dcache-call-api 'init-variables))

(defun pyim-dcache-get-variable (variable)
  "从 `pyim-dcache-directory' 中读取与 VARIABLE 对应的文件中保存的值."
  (let ((file (expand-file-name (symbol-name variable)
                                pyim-dcache-directory)))
    (pyim-dcache-get-value-from-file file)))

(defun pyim-dcache-set-variable (variable &optional force-restore fallback-value)
  "设置变量.

如果 VARIABLE 的值为 nil, 则使用 ‘pyim-dcache-directory’ 中对应文件的内容来设置
VARIABLE 变量，FORCE-RESTORE 设置为 t 时，强制恢复，变量原来的值将丢失。
如果获取的变量值为 nil 时，将 VARIABLE 的值设置为 FALLBACK-VALUE ."
  (when (or force-restore (not (symbol-value variable)))
    (let ((file (expand-file-name (symbol-name variable)
                                  pyim-dcache-directory)))
      (set variable (or (pyim-dcache-get-value-from-file file)
                        fallback-value
                        (make-hash-table :test #'equal))))))

(defun pyim-dcache-save-variable (variable)
  "将 VARIABLE 变量的取值保存到 `pyim-dcache-directory' 中对应文件中."
  (let ((file (expand-file-name (symbol-name variable)
                                pyim-dcache-directory))
        (value (symbol-value variable)))
    (pyim-dcache-save-value-to-file value file)))

(defun pyim-dcache-save-value-to-file (value file)
  "将 VALUE 保存到 FILE 文件中."
  (when value
    (with-temp-buffer
      ;; FIXME: We could/should set the major mode to `lisp-data-mode'.
      (insert ";; Auto generated by `pyim-dhashcache-save-variable-to-file', don't edit it by hand!\n")
      (insert (format ";; Build time: %s\n\n" (current-time-string)))
      (insert (prin1-to-string value))
      (insert "\n\n")
      (insert ";; Local\sVariables:\n") ;Use \s to avoid a false positive!
      (insert ";; coding: utf-8-unix\n")
      (insert ";; End:")
      (make-directory (file-name-directory file) t)
      (let ((save-silently t))
        (pyim-dcache-write-file file)))))

(defun pyim-dcache-get-value-from-file (file)
  "读取保存到 FILE 里面的 value."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((output
             (condition-case nil
                 (read (current-buffer))
               (error nil))))
        (unless output
          ;; 有时候词库缓存会发生错误，这时候，就将词库缓存转存到一个
          ;; 带时间戳的文件中，方便用户手动修复。
          (write-file (concat file "-dump-" (format-time-string "%Y%m%d%H%M%S"))))
        output))))

;; ** Dcache 文件处理功能
(defun pyim-dcache-write-file (filename &optional confirm)
  "A helper function to write dcache files."
  (let ((coding-system-for-write 'utf-8-unix))
    (when (and confirm
               (file-exists-p filename)
               ;; NS does its own confirm dialog.
               (not (and (eq (framep-on-display) 'ns)
                         (listp last-nonmenu-event)
                         use-dialog-box))
               (or (y-or-n-p (format-message
                              "File `%s' exists; overwrite? " filename))
                   (user-error "Canceled"))))
    (write-region (point-min) (point-max) filename nil :silent)
    (message "Saving file %s..." filename)))

(defun pyim-dcache-save-caches ()
  "保存 dcache.

  将用户选择过的词生成的缓存和词频缓存的取值
  保存到它们对应的文件中.

  这个函数默认作为 `kill-emacs-hook' 使用。"
  (interactive)
  (pyim-dcache-call-api 'save-personal-dcache-to-file)
  t)

;; ** Dcache 导出功能
(defalias 'pyim-export 'pyim-dcache-export)
(defun pyim-dcache-export (file &optional confirm)
  "将个人词条以及词条对应的词频信息导出到文件 FILE.

  如果 FILE 为 nil, 提示用户指定导出文件位置, 如果 CONFIRM 为 non-nil，
  文件存在时将会提示用户是否覆盖，默认为覆盖模式"
  (interactive "F将词条相关信息导出到文件: ")
  (with-temp-buffer
    (insert ";;; -*- coding: utf-8-unix -*-\n")
    (pyim-dcache-call-api 'insert-export-content)
    (pyim-dcache-write-file file confirm)))

(defalias 'pyim-export-personal-words 'pyim-dcache-export-personal-words)
(defun pyim-dcache-export-personal-words (file &optional confirm)
  "将用户选择过的词生成的缓存导出为 pyim 词库文件.

如果 FILE 为 nil, 提示用户指定导出文件位置, 如果 CONFIRM 为 non-nil，
文件存在时将会提示用户是否覆盖，默认为覆盖模式。

注： 这个函数的用途是制作 pyim 词库，个人词条导入导出建议使用：
`pyim-dcache-import' 和 `pyim-dcache-export' ."
  (interactive "F将个人缓存中的词条导出到文件：")
  (pyim-dcache-call-api 'export-personal-words file confirm)
  (message "Pyim export finished."))

;; ** Dcache 导入功能
(declare-function pyim-create-word "pyim")

(defalias 'pyim-import 'pyim-dcache-import)
(defun pyim-dcache-import (file &optional merge-method)
  "从 FILE 中导入词条以及词条对应的词频信息。

MERGE-METHOD 是一个函数，这个函数需要两个数字参数，代表
词条在词频缓存中的词频和待导入文件中的词频，函数返回值做为合并后的词频使用，
默认方式是：取两个词频的最大值。"
  (interactive "F导入词条相关信息文件: ")
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix))
      (insert-file-contents file))
    (goto-char (point-min))
    (forward-line 1)
    (while (not (eobp))
      (let* ((content (pyim-dline-parse))
             (word (car content))
             (count (string-to-number
                     (or (car (cdr content)) "0"))))
        (pyim-create-word
         word nil
         (lambda (x)
           (funcall (or merge-method #'max)
                    (or x 0)
                    count))))
      (forward-line 1)))
  ;; 保存一下用户选择过的词生成的缓存和词频缓存，
  ;; 因为使用 async 机制更新 dcache 时，需要从 dcache 文件
  ;; 中读取变量值, 然后再对用户选择过的词生成的缓存排序，如果没
  ;; 有这一步骤，导入的词条就会被覆盖。
  (pyim-dcache-save-caches)
  ;; 更新相关的 dcache
  (pyim-dcache-call-api 'update-personal-words t)

  (message "pyim: 词条相关信息导入完成！"))

;; ** Dcache 更新功能
(defun pyim-dcache-update (&optional force)
  "读取并加载所有相关词库 dcache.

如果 FORCE 为真，强制加载。"
  (pyim-dcache-init-variables)
  (pyim-dcache-update-personal-words force)
  (pyim-dcache-update-code2word force)
  ;; 这个命令 *当前* 主要用于五笔输入法。
  (pyim-dcache-update-shortcode2word force))

(defun pyim-dcache-update-code2word (&optional force)
  "读取并加载词库.

读取 `pyim-dicts' 和 `pyim-extra-dicts' 里面的词库文件，生成对应的
词库缓冲文件，然后加载词库缓存。

如果 FORCE 为真，强制加载。"
  (when pyim-dcache-auto-update
    (let* ((dict-files (mapcar (lambda (x)
                                 (unless (plist-get x :disable)
                                   (plist-get x :file)))
                               `(,@pyim-dicts ,@pyim-extra-dicts)))
           (dicts-md5 (pyim-dcache-create-dicts-md5 dict-files)))
      (pyim-dcache-call-api 'update-code2word dict-files dicts-md5 force))))

(defun pyim-dcache-create-dicts-md5 (dict-files)
  (let* ((version "v1") ;当需要强制更新 dict 缓存时，更改这个字符串。
         (dicts-md5 (md5 (prin1-to-string
                          (mapcar (lambda (file)
                                    (list version file (nth 5 (file-attributes file 'string))))
                                  dict-files)))))
    dicts-md5))

(defun pyim-dcache-update-personal-words (&optional force)
  "更新个人缓存词库。
如果 FORCE non-nil, 则强制更新。"
  (when pyim-dcache-auto-update
    (pyim-dcache-call-api 'update-personal-words force)))

(defun pyim-dcache-update-shortcode2word (&optional force)
  "更新 shortcode2word 缓存。

如果 FORCE non-nil, 则强制更新。"
  (when pyim-dcache-auto-update
    (pyim-dcache-call-api 'update-shortcode2word force)))

(defun pyim-dcache-update-iword2count (word &optional prepend wordcount-handler)
  "保存词频到缓存."
  (pyim-dcache-call-api 'update-iword2count word prepend wordcount-handler))

(defun pyim-dcache-search-word-code (word)
  "搜素中文词条 WORD 对应的 code."
  (pyim-dcache-call-api 'search-word-code word))

;; ** Dcache 加词功能
(defun pyim-dcache-insert-icode2word (word pinyin prepend)
  "保存个人词到缓存."
  (pyim-dcache-call-api 'insert-word-into-icode2word word pinyin prepend))

;; ** Dcache 升级功能
(defun pyim-dcache-upgrade-icode2word ()
  "升级个人词库缓存.

主要是将个人词库中旧的 code-prefix 升级为新的 code-prefix. 用到
scheme 中的 :code-prefix-history 信息。"
  (interactive)
  (pyim-dcache-call-api 'upgrade-icode2word))

;; ** Dcache 删词功能
(defun pyim-dcache-delete-word (word)
  "将中文词条 WORD 从个人词库中删除"
  (pyim-dcache-call-api 'delete-word word))

;; ** Dcache 检索功能
(defun pyim-dcache-get (code &optional from)
  "从 FROM 对应的 dcache 中搜索 CODE, 得到对应的词条.

当词库文件加载完成后，pyim 就可以用这个函数从词库缓存中搜索某个
code 对应的中文词条了."
  (pyim-dcache-call-api 'get code from))

;; ** 分割 code
(defun pyim-dcache-code-split (code)
  "将 CODE 分成 code-prefix 和 rest code."
  (cond
   ;; 处理 nil
   ((not code) nil)
   ;; 兼容性代码：旧版本的 pyim 使用一个标点符号作为 code-prefix
   ((pyim-string-match-p "^[[:punct:]]" code)
    (list (substring code 0 1) (substring code 1)))
   ;; 拼音输入法不使用 code-prefix, 并且包含 -
   ((pyim-string-match-p "-" code)
    (list "" code))
   ((not (pyim-string-match-p "[[:punct:]]" code))
    (list "" code))
   ;; 新 code-prefix 使用类似 "wubi/" 的格式。
   (t (let ((x (split-string code "/")))
        (list (concat (nth 0 x) "/")
              (nth 1 x))))))

;; * Footer
(provide 'pyim-dcache)

;;; pyim-dcache.el ends here
