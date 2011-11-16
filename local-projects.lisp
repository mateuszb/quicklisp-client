;;;; local-projects.lisp

;;;
;;; Local project support.
;;;
;;; Local projects can be placed in <quicklisp>/local-projects/. New
;;; entries in that directory are automatically scanned for system
;;; files for use with QL:QUICKLOAD.
;;;
;;; This works by keeping a cache of system file pathnames in
;;; <quicklisp>/local-projects/system-index.txt. Whenever the
;;; timestamp on the local projects directory is newer than the
;;; timestamp on the system index file, the entire tree is re-scanned
;;; and cached.
;;;
;;; This will pick up system files that are created as a result of
;;; creating new project directory in <quicklisp>/local-projects/,
;;; e.g. unpacking a tarball or zip file, checking out a project from
;;; version control, etc. It will NOT pick up a system file that is
;;; added sometime later in a subdirectory; for that, the
;;; REGISTER-LOCAL-PROJECTS function is needed to rebuild the system
;;; file index.
;;;
;;; In the event there are multiple systems of the same name in the
;;; directory tree, the one with the shortest pathname namestring is
;;; used. This is intended to ignore stuff like _darcs pristine
;;; directories.
;;;
;;; Work in progress!
;;;

(in-package #:quicklisp-client)

(defparameter *local-project-directories*
  (list (qmerge "local-projects/"))
  "The default local projects directory.")

(defun system-index-file (pathname)
  "Return the system index file for the directory PATHNAME."
  (merge-pathnames "system-index.txt" pathname))

(defun local-project-system-files (pathname)
  "Return a list of system files under PATHNAME."
  (let ((wild (merge-pathnames "**/*.asd" pathname)))
    (sort (directory wild)
          #'<
          :key (lambda (file)
                 (length (namestring file))))))

(defun make-system-index (pathname)
  "Create a system index file for all system files under
PATHNAME. Current format is one native namestring per line."
  (with-open-file (stream (system-index-file pathname)
                          :direction :output
                          :if-exists :rename-and-delete)
    (dolist (system-file (local-project-system-files pathname))
      (let ((system-path (enough-namestring system-file pathname)))
        (write-line (native-namestring system-path) stream)))
    (probe-file stream)))

(defun find-valid-system-index (pathname)
  "Find a valid system index file for PATHNAME; one that both exists
and has a newer timestamp than PATHNAME."
  (let* ((file (system-index-file pathname))
         (probed (probe-file file)))
    (when (and probed
               (<= (directory-write-date pathname)
                   (file-write-date probed)))
      probed)))

(defun ensure-system-index (pathname)
  "Find or create a system index file for PATHNAME."
  (or (find-valid-system-index pathname)
      (make-system-index pathname)))

(defun find-system-in-index (system index-file)
  "If any system pathname in INDEX-FILE has a pathname-name matching
SYSTEM, return its full pathname."
  (with-open-file (stream index-file)
    (loop for namestring = (read-line stream nil)
          while namestring
          when (string= system (pathname-name namestring))
          return (truename (merge-pathnames namestring index-file)))))

(defun local-projects-searcher (system-name)
  "This function is added to ASDF:*SYSTEM-DEFINITION-SEARCH-FUNCTIONS*
to use the local project directory and cache to find systems."
  (dolist (directory *local-project-directories*)
    (when (probe-directory directory)
      (let ((system-index (ensure-system-index directory)))
        (when system-index
          (let ((system (find-system-in-index system-name system-index)))
            (when system
              (return system))))))))

(defun register-local-projects ()
  "Force a scan of the local projects directory to create the system
file index."
  (map nil 'make-system-index *local-project-directories*))
