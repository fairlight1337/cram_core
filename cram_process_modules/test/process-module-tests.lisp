;;; Copyright (c) 2012, Lorenz Moesenlechner <moesenle@in.tum.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of the Intelligent Autonomous Systems Group/
;;;       Technische Universitaet Muenchen nor the names of its contributors 
;;;       may be used to endorse or promote products derived from this software 
;;;       without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :cram-process-module-tests)

(defun run-process-module-tests ()
  (run-tests))

(defclass test-designator (desig:designator) ())

(desig:register-designator-class test test-designator)

(defmethod desig:reference ((designator test-designator) &optional role)
  (declare (ignore role))
  (desig:properties designator))

(def-process-module test-process-module (input)
  (funcall (desig:reference input)))

(define-test process-module-execution
  (let* ((process-module-executed nil)
             (designator (desig:make-designator
                          'test (lambda ()
                                  (setf process-module-executed t)))))
        (assert-false process-module-executed)
    (cpl:top-level
      (with-process-modules-running (test-process-module)
        (pm-execute 'test-process-module designator)))
    (assert-true process-module-executed)))

(define-condition process-module-test-error (error) ())

(define-test process-module-execution-error
  (let* ((condition (make-condition 'process-module-test-error))
         (caught-condition nil)
         (designator (desig:make-designator
                      'test (lambda ()
                              (error condition))))
         (lock (sb-thread:make-mutex))
         (waitqueue (sb-thread:make-waitqueue)))
    (assert-error
     'process-module-test-error
     (let ((*process-module-debugger-hook*
             (lambda (condition hook)
               (declare (ignore hook))
               (sb-thread:with-mutex (lock)
                 (setf caught-condition condition)
                 (sb-thread:condition-broadcast waitqueue)
                 (invoke-restart 'continue-pm))))
           (cpl-impl:*debug-on-lisp-errors* nil))
       (cpl:top-level
         (with-process-modules-running (test-process-module)
           (pm-execute 'test-process-module designator)
           ;; Wait for the debugger hook to run to get the caught
           ;; condition.
           (sb-thread:with-mutex (lock)
             (loop until caught-condition
                   do (sb-thread:condition-wait waitqueue lock)))))))
    (assert-eq condition caught-condition)))

(define-test cancel-on-evaporation
  (let* ((started nil)
         (done nil)
         (designator (desig:make-designator
                      'test (lambda ()
                              (setf started t)
                              (cpl:sleep 10)
                              (setf done t)))))
    (cpl:top-level
      (with-process-modules-running (test-process-module)
        (cpl:pursue
          (pm-execute 'test-process-module designator)
          (cpl:sleep 0.2))))
    (assert-true started)
    (assert-false done)))

(define-test restart-on-suspension
  (let* ((runs 0)
         (done nil)
         (designator (desig:make-designator
                      'test (lambda ()
                              (incf runs)
                              (cpl:sleep 0.2)
                              (setf done t)))))
    (cpl:top-level
      (cpl:with-tags
        (with-process-modules-running (test-process-module)
          (cpl:par
            (:tag execute
              (pm-execute 'test-process-module designator))
            (cpl-impl:with-task-suspended (execute)
              (cpl:sleep 0.2))))))
    (assert-eql 2 runs)
    (assert-true done)))

(define-test execution-during-suspension
  (let* ((counter 0)
         (a-run nil)
         (b-run nil)
         (designator-1 (desig:make-designator
                        'test (lambda ()
                                (cpl:sleep 0.2)
                                (setf a-run (incf counter)))))
         (designator-2 (desig:make-designator
                        'test (lambda ()
                                (cpl:sleep 0.2)
                                (setf b-run (incf counter))))))
    (cpl:top-level
      (cpl:with-tags
        (with-process-modules-running (test-process-module)
          (cpl:par
            (:tag execute
              (pm-execute 'test-process-module designator-1))
            (cpl-impl:with-task-suspended (execute)
              (pm-execute 'test-process-module designator-2)
              (cpl:sleep 0.2))))))
    (assert-eql 2 a-run)
    (assert-eql 1 b-run)))
