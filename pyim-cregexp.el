;;; pyim-cregexp.el --- Chinese regexp tools for pyim.        -*- lexical-binding: t; -*-

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
(require 'pyim-dcache)
(require 'pyim-imobjs)
(require 'pyim-pymap)
(require 'pyim-scheme)
(require 'rx)
(require 'xr)

(defgroup pyim-cregexp nil
  "Chinese regexp tools for pyim."
  :group 'pyim)

(defcustom pyim-cregexp-fallback-scheme 'quanpin
  "`pyim-cregexp-build' 使用的 Fallback scheme.

如果 `pyim-cregexp-build' 无法支持用户正在使用的 scheme 时，
将使用这个 scheme."
  :type 'symbol)

(defcustom pyim-cregexp-convert-at-point-function
  #'pyim-cregexp-convert-at-point-function
  "`pyim-cregexp-convert-at-point' 使用的函数。

此函数有一个参数 cregexp, 表示生成的 cregexp. 其返回值会插入当前
buffer."
  :type 'function)

(defun pyim-cregexp-char-level-num (num)
  "根据 NUM 返回一个有效的常用汉字级别。"
  (if (numberp num)
      (max (min num 4) 1)
    4))

(defun pyim-cregexp-build (string &optional char-level-num chinese-only)
  "根据 STRING 构建一个中文 regexp, 用于 \"拼音搜索汉字\".

比如：\"nihao\" -> \"[你呢...][好号...] \\| nihao\"


CHAR-LEVEL-NUM 代表汉字常用级别，pyim 中根据汉字的使用频率，将汉
字分为4个级别：1级最常用，4级别最不常用，1-3级汉字大概8000左右，
如果这个参数设置为3, 那么代表在构建 regexp 是，只使用常用级别小于
等于3的汉字。

如果 CHINESE-ONLY 为真，那么生成的 regexp 只能搜索汉字。

注意事项：如果生成的 regexp 太长，Emacs 无法处理，那么，这个命令
会抛弃一些不常用的汉字，重新生成，知道生成一个 Emacs 可以处理的
regexp, 所以搜索单字的时候一般可以搜到生僻字，但搜索句子的时候，
就无法搜索生僻字了。"
  ;; NOTE: (rx-to-string "") will return "\\(?:\\)",
  ;; While I want (pyim-cregexp-build "") return just "".
  (if (equal string "")
      string
    (let ((num (pyim-cregexp-char-level-num char-level-num))
          rx-string)
      (while (not (pyim-cregexp-valid-p rx-string))
        (setq rx-string
              (or (ignore-errors
                    (rx-to-string
                     (pyim-cregexp-build-from-rx
                      (lambda (x)
                        (if (stringp x)
                            (xr (pyim-cregexp-build-1 x num chinese-only))
                          x))
                      (xr string))))
                  string))
        (setq num (1- num)))
      rx-string)))

(defun pyim-cregexp-valid-p (cregexp)
  "Return t when cregexp is a valid regexp."
  (and cregexp
       (stringp cregexp)
       (condition-case nil
           (progn (string-match-p cregexp "") t)
         ;; FIXME: Emacs can't handle regexps whose length is too big :-(
         (error nil))))

(defun pyim-cregexp-build-from-rx (fn rx-form)
  (pcase rx-form
    ('nil nil)
    (`(,form) (funcall fn form))
    (`(any . ,_) rx-form)
    (`(,_ . ,_)
     (mapcar (lambda (x)
               (pyim-cregexp-build-from-rx fn x))
             rx-form))
    (_ (funcall fn rx-form))))

(defun pyim-cregexp-build-1 (str &optional char-level-num chinese-only)
  (let* ((num (pyim-cregexp-char-level-num char-level-num))
         (scheme-name (pyim-scheme-name))
         (class (pyim-scheme-get-option scheme-name :class))
         (code-prefix (pyim-scheme-get-option scheme-name :code-prefix))
         (sep "#####&&&&#####")
         (lst (remove "" (split-string
                          (replace-regexp-in-string
                           "\\([a-z]+'*\\)" (concat sep "\\1" sep) str)
                          sep))))
    ;; 确保 pyim 词库加载
    (pyim-dcache-init-variables)
    ;; pyim 暂时只支持全拼和双拼搜索
    (when (not (member class '(quanpin shuangpin xingma)))
      (setq scheme-name pyim-cregexp-fallback-scheme))
    (mapconcat
     (lambda (string)
       (if (or (pyim-string-match-p "[^a-z']+" string)
               (equal string ""))
           string
         (let* ((string1 (replace-regexp-in-string "'" "" string))
                (imobjs (pyim-imobjs-create string1 scheme-name))
                (regexp-list
                 (mapcar
                  (lambda (imobj)
                    (if (eq class 'xingma)
                        (pyim-cregexp-build:xingma imobj nil nil nil code-prefix)
                      (pyim-cregexp-build:quanpin imobj nil nil nil num)))
                  imobjs))
                (regexp
                 (when regexp-list
                   (string-join (delq nil regexp-list) "\\|")))
                (regexp
                 (if chinese-only
                     regexp
                   (if (> (length regexp) 0)
                       (if (equal string string1)
                           (concat string "\\|" regexp)
                         (concat string "\\|" string1 "\\|" regexp))
                     string))))
           (format "\\(?:%s\\)" regexp))))
     lst "")))

(defun pyim-cregexp-build:quanpin (imobj &optional match-beginning
                                         first-equal all-equal char-level-num)
  "从 IMOBJ 创建一个搜索中文的 regexp."
  (let* ((num (pyim-cregexp-char-level-num char-level-num))
         (imobj (mapcar (lambda (x)
                          (concat (nth 0 x) (nth 1 x)))
                        imobj))
         (cchar-list
          (let ((n 0) results)
            (dolist (py imobj)
              (let* ((equal-match
                      (or all-equal
                          (and first-equal (= n 0))))
                     (cchars
                      (mapconcat (lambda (x)
                                   (mapconcat #'identity
                                              (let* ((list (split-string x "|"))
                                                     (length (length list)))
                                                (cl-subseq list 0 (min num length)))
                                              ""))
                                 (pyim-pymap-py2cchar-get py equal-match nil t) "")))
                (push cchars results))
              (setq n (+ 1 n)))
            (nreverse results)))
         (regexp
          (mapconcat (lambda (x)
                       (when (pyim-string-match-p "\\cc" x)
                         (format "[%s]" x)))
                     cchar-list "")))
    (unless (equal regexp "")
      (concat (if match-beginning "^" "") regexp))))

(defun pyim-cregexp-build:xingma (imobj &optional match-beginning
                                        first-equal _all-equal code-prefix)
  "从 IMOBJ 创建一个搜索中文的 regexp."
  (cl-flet ((build-regexp
              (list)
              (let* ((n (apply #'max (mapcar #'length list)))
                     results)
                (dotimes (i n)
                  (push (format "[%s]%s"
                                (mapconcat
                                 (lambda (x)
                                   (if (> i (- (length x) 1))
                                       ""
                                     (char-to-string
                                      (elt x i))))
                                 list "")
                                (if (> i 0) "?" ""))
                        results))
                (string-join (reverse results)))))
    (let ((regexp (mapconcat
                   (lambda (x)
                     (let ((code (concat (or code-prefix "")
                                         (if first-equal
                                             (substring x 0 1)
                                           x))))
                       (build-regexp (pyim-dcache-get code))))
                   imobj "")))
      (unless (equal regexp "")
        (concat (if match-beginning "^" "") regexp)))))

(defun pyim-cregexp-convert-at-point (&optional insert-only)
  "将光标前的字符串按拼音的规则转换为一个搜索中文的 regexp.
用于实现拼音搜索中文的功能。

在 minibuffer 中，这个命令默认会自动运行 `exit-minibuffer'.
这个可以使用 INSERT-ONLY 参数控制。"
  (interactive "P")
  (pyim-pymap-cache-create)
  (let* ((string (if mark-active
                     (buffer-substring-no-properties
                      (region-beginning) (region-end))
                   (buffer-substring
                    (point)
                    (save-excursion
                      (skip-syntax-backward "w")
                      (point)))))
         (length (length string))
         (cregexp (pyim-cregexp-build string)))
    (delete-char (- 0 length))
    (insert (funcall pyim-cregexp-convert-at-point-function cregexp))
    (when (and (not insert-only)
               (window-minibuffer-p))
      (exit-minibuffer))))

(defun pyim-cregexp-convert-at-point-function (cregexp)
  "这个函数是变量 `pyim-cregexp-convert-at-point-function' 的默认取值。"
  (cond
   ;; Deal with `org-search-view'
   ((and (window-minibuffer-p)
         (string-match-p
          (regexp-quote "[+-]Word/{Regexp}")
          (buffer-substring (point-min) (point-max))))
    (format "{%s}" cregexp))
   (t cregexp)))

;; * Footer
(provide 'pyim-cregexp)

;;; pyim-cregexp.el ends here
