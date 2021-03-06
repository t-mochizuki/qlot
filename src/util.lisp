(in-package :cl-user)
(defpackage qlot.util
  (:use :cl)
  (:import-from :qlot.asdf
                :system-quicklisp-home)
  (:export :with-quicklisp-home
           :with-package-functions
           :pathname-in-directory-p
           :find-qlfile
           :call-in-local-quicklisp
           :with-local-quicklisp
           :ensure-installed-in-local-quicklisp))
(in-package :qlot.util)

(defmacro with-quicklisp-home (qlhome &body body)
  `(flet ((main () ,@body))
     (eval `(let ((,(intern #.(string :*quicklisp-home*) :ql) ,,qlhome)) (funcall ,#'main)))))

(defmacro with-package-functions (package-designator functions &body body)
  (let ((args (gensym "ARGS")))
    `(flet (,@(loop for fn in functions
                    collect `(,fn (&rest ,args)
                                  (apply
                                   ,(if (and (listp fn) (eq (car fn) 'setf))
                                        `(eval `(function (setf ,(intern ,(string (cadr fn)) ,package-designator))))
                                        `(symbol-function (intern ,(string fn) ,package-designator)))
                                   ,args))))
       ,@body)))

(defun pathname-in-directory-p (path directory)
  (loop for dir1 in (pathname-directory directory)
        for dir2 in (pathname-directory path)
        unless (string= dir1 dir2)
          do (return nil)
        finally
           (return t)))

(defun find-qlfile (directory &key (errorp t) use-lock)
  (check-type directory pathname)
  (unless #+clisp (ext:probe-directory directory)
          #-clisp (probe-file directory)
    (error "~S does not exist." directory))
  (let ((qlfile (merge-pathnames (if use-lock
                                     "qlfile.lock"
                                     "qlfile")
                                 directory)))
    (unless (probe-file qlfile)
      (when errorp
        (error "'~A' is not found at '~A'." qlfile directory))
      (setf qlfile nil))

    qlfile))

(defun call-in-local-quicklisp (fn system qlhome)
  (unless #+clisp (ext:probe-directory qlhome)
          #-clisp (probe-file qlhome)
    (error "Directory ~S does not exist." qlhome))

  (let (#+quicklisp
        (ql:*quicklisp-home* qlhome)
        (asdf::*source-registry* (make-hash-table :test 'equal))
        (asdf::*default-source-registries*
          '(asdf::environment-source-registry
            asdf::system-source-registry
            asdf::system-source-registry-directory))
        (asdf::*defined-systems* (make-hash-table :test 'equal))
        (asdf:*central-registry* (list (asdf:system-source-directory system))))

    (asdf::clear-defined-systems)

    #-quicklisp
    (load (merge-pathnames #P"quicklisp/setup.lisp" qlhome))
    #+quicklisp
    (push (merge-pathnames #P"quicklisp/" qlhome) asdf:*central-registry*)

    (asdf:initialize-source-registry)

    (funcall fn)))

(defmacro with-local-quicklisp (system &body body)
  (let ((qlot-dir (gensym "QLOT-DIR"))
        (system-dir (gensym "SYSTEM-DIR"))
        (register-directory (gensym "REGISTER-DIRECTORY")))
    `(let ((,qlot-dir (asdf:system-source-directory :qlot))
           (,system-dir (asdf:system-source-directory ,system)))
       (flet ((,register-directory (directory)
                (map nil
                     (lambda (asd)
                       (setf (gethash (pathname-name asd) asdf::*source-registry*) asd))
                     (asdf::directory-asd-files directory))))
         (call-in-local-quicklisp
          (lambda ()
            (,register-directory ,system-dir)
            (,register-directory ,qlot-dir)
            ,@body)
          ,system
          (system-quicklisp-home (asdf:find-system ,system)))))))

(defun ensure-installed-in-local-quicklisp (system qlhome)
  (with-package-functions :ql-dist (find-system required-systems name ensure-installed)
    (call-in-local-quicklisp
     (lambda ()
       (labels ((system-dependencies (system-name)
                  (let ((system (find-system (string-downcase system-name))))
                    (when system
                      (cons system
                            (mapcan #'system-dependencies (copy-list (required-systems system))))))))
         (map nil #'ensure-installed
              (delete-duplicates (mapcan #'system-dependencies
                                         (copy-list (asdf::component-sideway-dependencies system)))
                                 :key #'name
                                 :test #'string=))))
     system
     qlhome)))
