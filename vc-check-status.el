;;; vc-check-status.el --- Warn you when quitting emacs and leaving repo dirty.

;; Copyright (C) 2012-2013 Sylvain Rousseau <thisirs at gmail dot com>

;; Author: Sylvain Rousseau <thisirs at gmail dot com>
;; Keywords: vc, convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package warns you when a local repository is in a state that
;; needs to be changed before quitting emacs. For example, it is able
;; to warn you when there are some unpushed commits or if the
;; repository is dirty. The functions of the form
;; `vc-<BACKEND>-check-*-p' perform the check. The checks are
;; controlled in two ways: The buffer-local variable `vc-check'
;; specifies the checks to perform. If it is not set, the associative
;; list `vc-check-alist' is looked into.


(defvar vc-check-alist
  '((".*" unpushed changes))
  "Alist of file-name patterns vs corresponding states to check.
  The list of the checks currently implemented is: dirty,
  dirty-ignore-submodule, changes, untracked, unpushed.")

(defvar vc-check nil
  "List of states to check.")
(make-variable-buffer-local 'vc-check)
(put 'vc-check 'safe-local-variable 'vc-check-safe-p)

(defun vc-check-safe-p (keywords)
  (and (listp keywords)
       (let ((list (mapcar #'car vc-sym-name))
             (safe t))
         (while (and safe keywords)
           (setq safe (memq (car keywords) list)
                 keywords (cdr keywords)))
         (null (null safe)))))

(defun vc-check--responsible-backend (file)
  "Return nil if FILE is not under a version controlled system.
Return the version controlled system."
  (catch 'found
    (dolist (backend vc-handled-backends)
      (let ((path (vc-call-backend backend 'responsible-p file)))
        (if path (throw 'found (list path backend)))))))

(defun vc-check--get-repositories ()
  "Return a list of elements of the form (PATH BACKEND
KEYWORDS...) where PATH is the path to a repository, BACKEND
its backend and KEYWORDS the list of the checks to perform on it
when quitting."
  (let (result)
    (dolist (buffer (buffer-list) result)
      (let* ((file (buffer-file-name buffer)))
        (when file
          (let ((backend (vc-check--responsible-backend file)))
            (unless (or (not backend) (assoc (car backend) result))
              (let (temp)
                (cond
                 ((local-variable-p 'vc-checks buffer)
                  (push (append backend (buffer-local-value vc-checks)) result))
                 ((setq temp (assoc-default (car backend) vc-check-alist 'string-match))
                  (push (append backend temp) result)))))))))
    result))

(defun vc-check-repositories ()
  "Check all known repos and ask for confirmation.
This function first lists all known repositories. Then for every
one of them, it checks if they are clean. If not, it asks you if
you really want to quit."
  (interactive)
  (let* ((repos (vc-check--get-repositories)))
    (while (and repos (vc-check--repository-ok (car repos)))
      (setq repos (cdr repos)))
    (null repos)))

(defun vc-check--repository-ok (repo)
  "Return non-nil if the repository described by REPO passed the
specified checks."
  (let* ((default-directory (car repo))
         (checks (cddr repo))
         (backend (downcase (symbol-name (cadr repo))))
         checks-ok
         error)

    (setq checks-ok
          (delete
           nil
           (mapcar
            (lambda (check)
              (if (condition-case e
                      (progn
                        (require (intern (format "vc-%s-check-status" backend)))
                        (funcall
                         (intern
                          (format "vc-%s-check-%s-p" backend check))))
                    (error (setq error e)))
                  check))
            checks)))

    (if error
        (yes-or-no-p
         (format "An error occurred on repo %s: %s; Exit anyway?"
                 (car repo) error))
      (or
       (not checks-ok)
       ;; if repo is an autocommited one, we don't need
       ;; to warn user
       (and
        (fboundp 'vc-git-auto-committed-repo-p)
        (vc-git-auto-committed-repo-p))
       (yes-or-no-p
        (format "You have %s in repository %s; Exit anyway?"
                (mapconcatend
                 (lambda (e)
                   (assoc-default e (intern (format "vc-%s-sym-name" backend))))
                 checks-ok ", " " and ")
                default-directory))))))


;;;###autoload
(defun vc-check-status-activate (&optional arg)
  (interactive "P")
  (if (< (prefix-numeric-value arg) 0)
      (remove-hook 'kill-emacs-query-functions 'vc-check-repositories)
    (add-hook 'kill-emacs-query-functions 'vc-check-repositories)))


;; Helper functions

(defun mapconcatend (func list separator last-separator)
  "Like mapconcat but the last separator can be specified. Useful
when building sentence like blah, blih, bloh and bluh."
  (let ((beg (butlast list))
        (end (car (last list))))
    (if beg
        (concat (mapconcat func beg separator) last-separator
                (funcall func end))
      (funcall func end))))

(provide 'vc-check-status)

;;; vc-check-status.el ends here