;;; pyim-dict.el --- Dict core tools for pyim.        -*- lexical-binding: t; -*-

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

(defgroup pyim-dict nil
  "Dict tools for pyim."
  :group 'pyim)

(defcustom pyim-dicts nil
  "一个列表，用于保存 `pyim' 的词库信息.
每一个 element 都代表一条词库的信息, 用户可以使用词库管理命令
`pyim-dicts-manager' 来添加词库信息，每一条词库信息都使用一个
plist 来表示，比如：

    (:name \"100万大词库\" :file \"/path/to/pinyin-bigdict.pyim\")

其中：
1. `:name'      代表词库名称，用户可以按照喜好来确定（可选项）。
2. `:file'      表示词库文件，

另外一个与这个变量功能类似的变量是： `pyim-extra-dicts', 专门
用于和 elpa 格式的词库包集成。"
  :type 'list)

(defvar pyim-extra-dicts nil "与 `pyim-dicts' 类似, 用于和 elpa 格式的词库包集成。.")

(defun pyim-extra-dicts-add-dict (new-dict)
  "添加 `new-dict' 到 `pyim-extra-dicts'.

其中 NEW-DICT 的格式为：

   (:name \"XXX\" :file \"/path/to/XXX.pyim\")

这个函数用于制作 elpa 格式的词库 ，不建议普通用户使用。"
  (let (replace result)
    (dolist (dict pyim-extra-dicts)
      (if (equal (plist-get dict :name)
                 (plist-get new-dict :name))
          (progn (push new-dict result)
                 (setq replace t))
        (push dict result)))
    (setq result (reverse result))
    (setq pyim-extra-dicts
          (if replace result `(,@result ,new-dict)))
    (message "Add pyim dict %S to `pyim-extra-dicts'." (plist-get new-dict :name))
    t))

(defun pyim-dict-name-available-p (dict-name)
  "查询 `pyim-dicts' 中 `:name' 为 DICT-NAME 的词库信息是否存在。
这个函数主要用于词库 package。"
  (cl-some (lambda (x)
             (let ((name (plist-get x :name)))
               (equal name dict-name)))
           pyim-dicts))

(defun pyim-dict-file-available-p (dict-file)
  "查询 `pyim-dicts' 中 `:file' 为 DICT-FILE 的词库信息是否存在。
这个函数主要用于词库 package。"
  (cl-some (lambda (x)
             (let ((file (plist-get x :file)))
               (equal (expand-file-name file)
                      (expand-file-name dict-file))))
           pyim-dicts))

;; * Footer
(provide 'pyim-dict)

;;; pyim-dict.el ends here
